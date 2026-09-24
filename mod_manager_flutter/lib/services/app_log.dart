import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/path_helper.dart';

enum LogLevel { debug, info, warn, error }

/// One line in the log, kept as data so the UI can show it without parsing.
class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String message;
  final String? details;

  const LogEntry({
    required this.time,
    required this.level,
    required this.message,
    this.details,
  });

  /// `2026-09-24 21:03:11.482  WARN  message`, with details indented below.
  String format() {
    final stamp = time.toIso8601String().replaceFirst('T', ' ');
    final tag = level.name.toUpperCase().padRight(5);
    final head = '$stamp  $tag  $message';

    if (details == null || details!.isEmpty) return head;
    return '$head\n${details!.trimRight().split('\n').map((l) => '    $l').join('\n')}';
  }
}

/// App-wide log: keeps the last lines in memory for the settings screen and
/// appends everything to a file on disk.
///
/// Exists because the only evidence for a freeze or a failed install used to
/// be whatever the user happened to see. A file that survives the crash and a
/// copyable tail turn "it froze once" into something with a timestamp.
class AppLog {
  AppLog._();

  static const int maxEntriesInMemory = 500;
  static const int maxFileBytes = 2 * 1024 * 1024;
  static const String fileName = 'modlinq.log';
  static const String previousFileName = 'modlinq.log.1';

  static final Queue<LogEntry> _entries = Queue<LogEntry>();
  static File? _file;

  /// Mirrors every entry to stdout. Off in release: the terminal is not where
  /// a packaged app is read from.
  static bool echoToConsole = false;

  static String get directoryPath => p.join(PathHelper.getAppDataPath(), 'logs');

  static String get filePath => p.join(directoryPath, fileName);

  /// Opens the log file. Safe to call more than once.
  static void init({String? directory}) {
    final dir = Directory(directory ?? directoryPath);
    dir.createSync(recursive: true);

    _file = File(p.join(dir.path, fileName));
    _rotateIfNeeded();
  }

  static void debug(String message, {Object? details}) =>
      write(LogLevel.debug, message, details: details);

  static void info(String message, {Object? details}) =>
      write(LogLevel.info, message, details: details);

  static void warn(String message, {Object? details}) =>
      write(LogLevel.warn, message, details: details);

  static void error(String message, {Object? error, StackTrace? stack}) => write(
    LogLevel.error,
    message,
    details: [
      if (error != null) '$error',
      if (stack != null) '$stack',
    ].join('\n'),
  );

  static void write(LogLevel level, String message, {Object? details}) {
    final entry = LogEntry(
      time: DateTime.now(),
      level: level,
      message: message,
      details: details?.toString(),
    );

    _entries.addLast(entry);
    while (_entries.length > maxEntriesInMemory) {
      _entries.removeFirst();
    }

    if (echoToConsole) {
      // ignore: avoid_print
      print(entry.format());
    }

    _append(entry);
  }

  /// Most recent entries, oldest first.
  static List<LogEntry> recent({int limit = maxEntriesInMemory}) {
    final entries = _entries.toList();
    if (entries.length <= limit) return entries;

    return entries.sublist(entries.length - limit);
  }

  /// The tail as text, for the "copy diagnostics" button.
  static String recentAsText({int limit = 200}) =>
      recent(limit: limit).map((entry) => entry.format()).join('\n');

  static void clear() => _entries.clear();

  static void _append(LogEntry entry) {
    final file = _file;
    if (file == null) return;

    try {
      file.writeAsStringSync('${entry.format()}\n', mode: FileMode.append);
      _rotateIfNeeded();
    } catch (_) {
      // A log that throws would be worse than no log.
    }
  }

  /// Keeps one previous file around, so a freeze that needs a restart does
  /// not take its own evidence with it.
  static void _rotateIfNeeded() {
    final file = _file;
    if (file == null || !file.existsSync()) return;
    if (file.lengthSync() < maxFileBytes) return;

    final previous = File(p.join(file.parent.path, previousFileName));
    if (previous.existsSync()) previous.deleteSync();

    file.renameSync(previous.path);
    _file = File(p.join(previous.parent.path, fileName));
  }
}
