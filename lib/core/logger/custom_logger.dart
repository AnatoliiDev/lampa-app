// ignore_for_file: avoid_print

import 'dart:io';

import 'package:loggy/loggy.dart';

class ConsolePrinter extends LoggyPrinter {
  const ConsolePrinter({this.showColors = false});

  final bool showColors;

  static final _levelColors = {
    LogLevel.debug: AnsiColor(foregroundColor: AnsiColor.grey(0.5), italic: true),
    LogLevel.info: AnsiColor(foregroundColor: 35),
    LogLevel.warning: AnsiColor(foregroundColor: 214),
    LogLevel.error: AnsiColor(foregroundColor: 196),
  };

  @override
  void onLog(LogRecord record) {
    final colorize = showColors && stdout.supportsAnsiEscapes;
    final time = record.time.toIso8601String().split('T')[1];
    final callerFrame = record.callerFrame == null ? ' ' : ' (${record.callerFrame?.location}) ';

    final String logLevel;
    if (colorize) {
      logLevel = record.level.name.toUpperCase().padRight(8);
    } else {
      logLevel = "[${record.level.name.toUpperCase()}]".padRight(10);
    }

    final color = showColors ? levelColor(record.level) ?? AnsiColor() : AnsiColor();

    print(color('$time $logLevel [${record.loggerName}]$callerFrame${record.message}'));

    if (record.stackTrace != null) {
      print(record.stackTrace);
    }
  }

  AnsiColor? levelColor(LogLevel level) {
    return _levelColors[level];
  }
}

class FileLogPrinter extends LoggyPrinter {
  FileLogPrinter(String filePath, {this.minLevel = LogLevel.debug}) : _logFile = File(filePath) {
    _rotateIfBig();
  }

  static const _maxBytes = 2 * 1024 * 1024;

  final File _logFile;
  final LogLevel minLevel;

  // Дописуємо, а не перезаписуємо. В оригіналі стояв FileMode.writeOnly, тобто
  // кожен запуск застосунку стирав попередній лог — а після падіння застосунок
  // саме що перезапускається і знищував рівно ті рядки, які пояснюють причину.
  late final _sink = _logFile.openWrite(mode: FileMode.writeOnlyAppend);

  /// Дописування без межі колись зайняло б памʼять пристрою, тому завеликий
  /// файл відкладаємо вбік — один попередній зріз лишається доступним.
  void _rotateIfBig() {
    try {
      if (_logFile.existsSync() && _logFile.lengthSync() > _maxBytes) {
        _logFile.renameSync('${_logFile.path}.1');
      }
    } catch (_) {
      // Не вийшло — не критично: гірше лише те, що файл росте далі.
    }
  }

  @override
  void onLog(LogRecord record) {
    final time = record.time.toIso8601String().split('T')[1];
    _sink.writeln("$time - $record");
    if (record.error != null) {
      _sink.writeln(record.error);
    }
    if (record.stackTrace != null) {
      _sink.writeln(record.stackTrace);
    }
    // Скидаємо на диск одразу. Інакше при падінні процесу останні рядки — саме
    // ті, заради яких усе й затівалося, — лишаються в буфері й гинуть з ним.
    _sink.flush().ignore();
  }

  void dispose() {
    _sink.close();
  }
}
