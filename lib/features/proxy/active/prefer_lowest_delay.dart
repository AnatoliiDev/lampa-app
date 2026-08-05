import 'dart:async';

import 'package:fpdart/fpdart.dart';

import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Ядро саме будує групу вибору каналу поверх нашого профілю і завжди ставить
/// типовим `balance` — почергове використання обох каналів. Перевизначити це з
/// профілю не можна: у `hiddify-core` (v2/config/builder.go) типовий вибір
/// жорстко перезаписується щоразу, коли каналів більше одного.
///
/// Нам потрібен `lowest`: він щоразу бере канал із меншою затримкою і сам
/// перемикається, коли той відмовляє. Це і є задум двох каналів — WireGuard
/// швидший, Reality проходить там, де ріжуть UDP. `balance` натомість половину
/// з'єднань відправляє в канал, який у цій мережі може бути мертвий.
///
/// Вибір ядро запам'ятовує у своєму кеші, тож підміняємо його один раз на
/// підключення, а далі не заважаємо: якщо користувач обрав канал вручну,
/// повторно не чіпаємо.
const _selectGroupTag = "select";
const _lowestDelayTag = "lowest";

final preferLowestDelayProvider = Provider<void>((ref) {
  final logger = _PreferLowestDelayLogger();
  final serviceRunning = ref.watch(serviceRunningProvider);
  if (!serviceRunning) return;

  var applied = false;
  final subscription = ref.read(proxyRepositoryProvider).watchProxies().listen((event) {
    if (applied) return;
    final group = event.getOrElse((_) => null);
    if (group == null || group.tag != _selectGroupTag) return;

    // Група ще не наповнилась — чекаємо наступної події.
    if (!group.items.any((e) => e.tag == _lowestDelayTag)) return;

    applied = true;
    if (group.selected == _lowestDelayTag) return;

    logger.loggy.info("канал: ${group.selected} → $_lowestDelayTag");
    unawaited(
      ref.read(proxyRepositoryProvider).selectProxy(_selectGroupTag, _lowestDelayTag).getOrElse((err) {
        logger.loggy.warning("не вдалося перемкнути канал", err);
        return unit;
      }).run(),
    );
  });

  ref.onDispose(subscription.cancel);
});

class _PreferLowestDelayLogger with AppLogger {}
