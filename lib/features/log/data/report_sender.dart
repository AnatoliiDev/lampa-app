import 'dart:convert';
import 'dart:io';

import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/log/data/log_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Скільки лог-файлу брати з кінця. Початок майже завжди марний — цікаве
/// відбувається перед падінням, а на сервері стоїть стеля на розмір тіла.
const _tailBytes = 120 * 1024;

class ReportSender with InfraLogger {
  ReportSender(this._ref);

  final Ref _ref;

  Future<String> _tail(File file) async {
    try {
      if (!file.existsSync()) return '';
      final length = await file.length();
      final from = length > _tailBytes ? length - _tailBytes : 0;
      final bytes = await file.openRead(from).expand((chunk) => chunk).toList();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (error) {
      return 'не вдалося прочитати ${file.path}: $error';
    }
  }

  /// Конфіги профілів, які лежать на пристрої. Саме їх отримує ядро, тож без
  /// них половина причин збою невидима. Приватні ключі WireGuard звідси не
  /// вирізаємо: сервер наш, а без ключів конфіг неможливо перевірити.
  Future<String> _configs() async {
    try {
      final dir = _ref.read(profilePathResolverProvider).directory;
      if (!dir.existsSync()) return '(теки конфігів немає)';

      final parts = <String>[];
      for (final entry in dir.listSync().whereType<File>()) {
        if (!entry.path.endsWith('.json')) continue;
        parts.add('# ${entry.path}\n${await entry.readAsString()}');
      }
      return parts.isEmpty ? '(конфігів немає)' : parts.join('\n\n');
    } catch (error) {
      return 'не вдалося прочитати конфіги: $error';
    }
  }

  /// Надсилає логи на сервер. Повертає ідентифікатор звіту — його можна
  /// продиктувати, щоб знайти потрібний серед інших.
  Future<String> send({String note = ''}) async {
    final paths = _ref.read(logPathResolverProvider);
    final info = await _ref.read(appInfoProvider.future);

    final payload = jsonEncode({
      'version': '${info.presentVersion} (${info.release.name})',
      'platform': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'note': note,
      'appLog': await _tail(paths.appFile()),
      'coreLog': await _tail(paths.coreFile()),
      'configs': await _configs(),
    });

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('${Constants.apiBase}/api/report'));
      request.headers.contentType = ContentType.json;
      request.write(payload);

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 201) {
        throw Exception('сервер відповів ${response.statusCode}: $body');
      }
      return (jsonDecode(body) as Map<String, dynamic>)['id'] as String;
    } finally {
      client.close();
    }
  }
}

final reportSenderProvider = Provider<ReportSender>(ReportSender.new);
