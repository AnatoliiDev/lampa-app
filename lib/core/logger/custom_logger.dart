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

  DateTime _lastFlush = DateTime.fromMillisecondsSinceEpoch(0);
  bool _broken = false;

  @override
  void onLog(LogRecord record) {
    // Логер не має права зламати те, що він логує. Під час bootstrap рядків
    // сотні, і виняток звідси — наприклад, якщо sink впав в помилку — обірвав
    // би сам запуск застосунку. Тому все загорнуте, а після першої поломки
    // друкуємо лише в консоль і більше файл не чіпаємо.
    if (_broken) return;
    try {
      final time = record.time.toIso8601String().split('T')[1];
      _sink.writeln("$time - $record");
      if (record.error != null) {
        _sink.writeln(record.error);
      }
      if (record.stackTrace != null) {
        _sink.writeln(record.stackTrace);
      }

      // Скидання на диск потрібне, щоб при падінні процесу не загубився хвіст —
      // саме він і пояснює причину. Але робити це на кожен рядок не можна:
      // паралельні flush() на одному файлі накопичуються й здатні вкинути sink
      // у помилку. Тому помилки скидаємо одразу, решту — не частіше разу на
      // півсекунди.
      final now = DateTime.now();
      if (record.level.priority >= LogLevel.warning.priority ||
          now.difference(_lastFlush) > const Duration(milliseconds: 500)) {
        _lastFlush = now;
        _sink.flush().ignore();
      }
    } catch (error, stackTrace) {
      _broken = true;
      // ignore: avoid_print
      print('FileLogPrinter вимкнено після помилки: $error\n$stackTrace');
    }
  }

  void dispose() {
    if (_broken) return;
    try {
      _sink.close();
    } catch (_) {
      // Закривати нема чого — і добре.
    }
  }
}
