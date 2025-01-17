import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/file_system/file_system.dart' hide File;
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as path;
import 'package:surveyor/src/driver.dart';
import 'package:surveyor/src/visitors.dart';

/// Looks for instances where "async" is used as an identifier
/// and would break were it made a keyword.
///
/// Run like so:
///
/// dart example/async_surveyor.dart <source dir>
main(List<String> args) async {
  if (args.length == 1) {
    final dir = args[0];
    if (!File('$dir/pubspec.yaml').existsSync()) {
      print("Recursing into '$dir'...");
      args = Directory(dir).listSync().map((f) => f.path).toList()..sort();
      dirCount = args.length;
      print('(Found $dirCount subdirectories.)');
    }
  }

  if (_debuglimit != null) {
    print('Limiting analysis to $_debuglimit packages.');
  }

  final driver = Driver.forArgs(args);
  driver.forceSkipInstall = true;
  driver.showErrors = false;
  driver.resolveUnits = false;
  driver.visitor = AsyncCollector();

  await driver.analyze();
}

int dirCount;

/// If non-zero, stops once limit is reached (for debugging).
int _debuglimit; //500;

class AsyncCollector extends RecursiveAstVisitor
    implements
        PostVisitCallback,
        PreAnalysisCallback,
        PostAnalysisCallback,
        AstContext {
  int count = 0;
  int contexts = 0;
  String filePath;
  Folder currentFolder;
  LineInfo lineInfo;
  Set<Folder> contextRoots = <Folder>{};

  // id: inDecl, notInDecl
  Map<String, Occurences> occurrences = <String, Occurences>{
    'async': Occurences(),
    'await': Occurences(),
    'yield': Occurences(),
  };

  List<String> reports = <String>[];

  AsyncCollector();

  @override
  void onVisitFinished() {
    print(
        'Found ${reports.length} occurrences in ${contextRoots.length} packages:');
    reports.forEach(print);

    for (var o in occurrences.entries) {
      final data = o.value;
      print('${o.key}: [${data.decls} decl, ${data.notDecls} ref]');
      data.packages.forEach(print);
    }
  }

  @override
  void postAnalysis(SurveyorContext context, DriverCommands cmd) {
    cmd.continueAnalyzing = _debuglimit == null || count < _debuglimit;
    // Reporting done in visitSimpleIdentifier.
  }

  @override
  void preAnalysis(SurveyorContext context,
      {bool subDir, DriverCommands commandCallback}) {
    if (subDir) {
      ++dirCount;
    }
    final contextRoot = context.analysisContext.contextRoot;
    currentFolder = contextRoot.root;
    final dirName = path.basename(contextRoot.root.path);

    print("Analyzing '$dirName' • [${++count}/$dirCount]...");
  }

  @override
  void setFilePath(String filePath) {
    this.filePath = filePath;
  }

  @override
  void setLineInfo(LineInfo lineInfo) {
    this.lineInfo = lineInfo;
  }

  @override
  visitSimpleIdentifier(SimpleIdentifier node) {
    final id = node.name;

    if (occurrences.containsKey(id)) {
      var occurrence = occurrences[id];
      if (node.inDeclarationContext()) {
        occurrence.decls++;
      } else {
        occurrence.notDecls++;
      }

      // cache/flutter_util-0.0.1 => flutter_util
      occurrence.packages
          .add(currentFolder.path.split('/').last.split('-').first);

      final location = lineInfo.getLocation(node.offset);
      final report =
          '$filePath:${location.lineNumber}:${location.columnNumber}';
      reports.add(report);
      final declDetail = node.inDeclarationContext() ? '(decl) ' : '';
      print("found '$id' $declDetail• $report");
      contextRoots.add(currentFolder);
      print(occurrences);
    }
    return super.visitSimpleIdentifier(node);
  }
}

class Occurences {
  int decls = 0;
  int notDecls = 0;
  Set<String> packages = <String>{};

  @override
  String toString() => '[$decls, $notDecls] : $packages';
}
