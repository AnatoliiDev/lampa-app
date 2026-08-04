import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/features/log/data/log_parser.dart';
import 'package:hiddify/features/log/data/log_path_resolver.dart';
import 'package:hiddify/features/log/model/log_entity.dart';
import 'package:hiddify/features/log/model/log_failure.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/utils/custom_loggers.dart';

abstract interface class LogRepository {
  TaskEither<LogFailure, Unit> init();
  Stream<Either<LogFailure, List<LogEntity>>> watchLogs();
  TaskEither<LogFailure, Unit> clearLogs();
}

class LogRepositoryImpl with ExceptionHandler, InfraLogger implements LogRepository {
  LogRepositoryImpl({required this.singbox, required this.logPathResolver});

  final HiddifyCoreService singbox;
  final LogPathResolver logPathResolver;

  /// Понад цю межу лог відкладається вбік замість того, щоб рости далі.
  static const _maxLogBytes = 2 * 1024 * 1024;

  /// Раніше тут стояло `writeAsString("")` — обидва логи затиралися при кожному
  /// запуску. Через це лог ядра завжди був порожній, а сесія, у якій щось
  /// зламалося, не доживала до моменту, коли її можна надіслати: щоб відкрити
  /// застосунок і натиснути «надіслати звіт», його треба запустити — а запуск
  /// уже стер докази. Тепер файл лише відкладається вбік, коли завеликий.
  Future<void> _prepare(File file) async {
    if (!await file.exists()) {
      await file.create(recursive: true);
      return;
    }
    if (await file.length() > _maxLogBytes) {
      await file.rename('${file.path}.1');
      await file.create(recursive: true);
    }
  }

  @override
  TaskEither<LogFailure, Unit> init() {
    return exceptionHandler(() async {
      if (!kIsWeb) {
        if (!await logPathResolver.directory.exists()) {
          await logPathResolver.directory.create(recursive: true);
        }
        await _prepare(logPathResolver.coreFile());
        await _prepare(logPathResolver.appFile());
      }
      return right(unit);
    }, LogUnexpectedFailure.new);
  }

  @override
  Stream<Either<LogFailure, List<LogEntity>>> watchLogs() {
    return singbox
        .watchLogs(logPathResolver.coreFile().path)
        .map((event) => event.map(LogParser.parseLogProto).toList())
        .handleExceptions((error, stackTrace) {
          loggy.warning("error watching logs", error, stackTrace);
          return LogFailure.unexpected(error, stackTrace);
        });
  }

  @override
  TaskEither<LogFailure, Unit> clearLogs() {
    return exceptionHandler(() => singbox.clearLogs().mapLeft(LogFailure.unexpected).run(), LogFailure.unexpected);
  }
}
