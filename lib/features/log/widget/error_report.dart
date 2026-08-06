import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/log/data/report_sender.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'error_report.g.dart';

/// Рядки тут навмисно не через slang: інтерфейс зафіксовано російською
/// (див. locale_preferences.dart), а заводити ключі в одинадцять локалей заради
/// одного діалогу зайве.
Future<void> showSendReportDialog(BuildContext context, WidgetRef ref, {String hint = ''}) async {
  final controller = TextEditingController(text: hint);
  final note = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Отправить отчёт об ошибке'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Логи приложения и ядра уйдут на сервер. Опишите в двух словах, '
            'что вы делали — так проще найти причину.',
          ),
          const Gap(12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Нажал «Подключить», приложение закрылось',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Отправить')),
      ],
    ),
  );
  if (note == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Отправляем…')));
  try {
    final id = await ref.read(reportSenderProvider).send(note: note);
    messenger.showSnackBar(SnackBar(content: Text('Отчёт отправлен: $id'), duration: const Duration(seconds: 8)));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('Не удалось отправить: $error')));
  }
}

/// Чи обірвався попередній запуск на пів дорозі.
///
/// Прапорець ставиться, щойно з'єднання піднялося, і знімається при звичайному
/// від'єднанні. Якщо застосунок загинув (а падіння в нативному коді вбиває весь
/// процес — жодного повідомлення людина не побачить), прапорець лишається, і на
/// наступному запуску ми самі пропонуємо надіслати звіт.
const _crashFlagKey = "unexpected_exit";

@riverpod
class UnexpectedExitNotifier extends _$UnexpectedExitNotifier with AppLogger {
  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider).requireValue;
    final crashed = prefs.getBool(_crashFlagKey) ?? false;
    if (crashed) {
      loggy.warning("попередній запуск обірвався несподівано, надсилаю звіт сам");
      // Знімаємо прапорець одразу: якщо надсилання не вдасться, краще втратити
      // один звіт, ніж надсилати його щоразу при відкритті застосунку.
      prefs.setBool(_crashFlagKey, false);
      unawaited(_sendSilently());
    }

    ref.listen(connectionNotifierProvider, (_, next) {
      final status = next.valueOrNull;
      if (status == null) return;
      if (status is Connected) {
        prefs.setBool(_crashFlagKey, true);
      } else if (status is Disconnected) {
        // Звичайне від'єднання — слідів не лишаємо. Якщо ж воно сталося через
        // помилку, кнопку й так покаже сам стан з'єднання.
        prefs.setBool(_crashFlagKey, false);
      }
    });

    return crashed;
  }

  /// Надсилає звіт без участі людини.
  ///
  /// Падіння в нативному коді вбиває процес мовчки: людина бачить лише, що
  /// застосунок зник, і переказати нам нічого не може. Просити її натиснути
  /// кнопку — означає втратити більшість випадків, а саме вони найцінніші.
  Future<void> _sendSilently() async {
    try {
      final id = await ref.read(reportSenderProvider).send(note: 'Автоматический отчёт: приложение закрылось само');
      loggy.info("звіт надіслано сам: $id");
    } catch (error) {
      loggy.warning("не вдалося надіслати звіт сам", error);
    }
  }

  /// Людина побачила пропозицію — більше не нагадуємо.
  void dismiss() {
    ref.read(sharedPreferencesProvider).requireValue.setBool(_crashFlagKey, false);
    state = false;
  }
}

/// Кнопка на головній: показується лише тоді, коли є про що звітувати.
class ErrorReportBanner extends HookConsumerWidget {
  const ErrorReportBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(connectionNotifierProvider).valueOrNull;
    final failure = status is Disconnected ? status.connectionFailure : null;
    // Стежимо за прапорцем: саме він запускає автоматичну відправку.
    ref.watch(unexpectedExitNotifierProvider);

    // Hiddify під час звичайного від'єднання на частку секунди виставляє стан
    // помилки (у логах це «CONNECTION FAILURE: createService» рівно тоді, коли
    // людина сама натиснула «Відключити»). Помилки насправді немає, а червоний
    // напис устигав блимнути. Тому чекаємо, поки стан устоїться.
    final failurePresent = failure != null;
    final failureSettled = useState(false);
    useEffect(() {
      if (!failurePresent) {
        failureSettled.value = false;
        return null;
      }
      final timer = Timer(const Duration(seconds: 2), () => failureSettled.value = true);
      return timer.cancel;
    }, [failurePresent]);

    // Про падіння більше не питаємо: звіт про нього йде сам, щойно застосунок
    // відкрився. Кнопка лишається для випадку, коли підключення не вдалося —
    // там людина може додати, що саме робила.
    if (!failurePresent || !failureSettled.value) return const SizedBox.shrink();

    const hint = 'Не удалось подключиться';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Что-то пошло не так',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          ),
          const Gap(8),
          FilledButton.tonalIcon(
            onPressed: () async {
              await showSendReportDialog(context, ref, hint: hint);
              ref.read(unexpectedExitNotifierProvider.notifier).dismiss();
            },
            icon: const Icon(Icons.bug_report_outlined, size: 20),
            label: const Text('Отправить отчёт об ошибке'),
          ),
        ],
      ),
    );
  }
}
