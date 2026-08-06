import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'overlay_permission_card.g.dart';

const _channel = MethodChannel('com.hiddify.app/method');

/// Чи дозволено показувати вікна поверх інших застосунків.
///
/// Це потрібно, щоб людина дізналася про мовчазний сервер, поки дивиться відео:
/// сповіщення в такий момент лягає у шторку, куди ніхто не заглядає. Дозвіл
/// особливий — система не дає просити його діалогом, лише відкрити свій екран
/// налаштувань, де перемикач вмикає сама людина.
@riverpod
Future<bool> canDrawOverlays(Ref ref) async {
  try {
    return await _channel.invokeMethod<bool>('can_draw_overlays') ?? true;
  } catch (_) {
    // На інших платформах питання не стоїть.
    return true;
  }
}

/// Показували вже картку чи людина від неї відмовилася.
const _dismissedKey = 'overlay_prompt_dismissed';

/// Одноразове прохання дозволити вікна поверх інших застосунків.
class OverlayPermissionCard extends ConsumerWidget with InfraLogger {
  const OverlayPermissionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final prefs = ref.watch(sharedPreferencesProvider).valueOrNull;
    if (prefs == null || (prefs.getBool(_dismissedKey) ?? false)) return const SizedBox.shrink();

    final granted = ref.watch(canDrawOverlaysProvider).valueOrNull ?? true;
    if (granted) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Разрешите показывать уведомления от приложения «Лампа» '
                'поверх других приложений',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
              const Gap(6),
              Text(
                'Вы сразу узнаете, если сервер перестанет отвечать.\n'
                // Без цього рядка людина потрапляє на екран зі списком програм і
                // не розуміє, що там робити.
                'На открывшемся экране включите переключатель для приложения «Лампа».',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Gap(12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () async {
                      await prefs.setBool(_dismissedKey, true);
                      ref.invalidate(canDrawOverlaysProvider);
                    },
                    child: const Text('Не сейчас'),
                  ),
                  const Gap(8),
                  FilledButton(
                    onPressed: () async {
                      // Відкриваємо потрібний перемикач одразу — шукати його в
                      // нетрях налаштувань людина не буде.
                      try {
                        await _channel.invokeMethod<void>('request_overlay_permission');
                      } catch (error) {
                        loggy.warning('не вдалося відкрити налаштування дозволу', error);
                      }
                    },
                    child: const Text('Разрешить'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
