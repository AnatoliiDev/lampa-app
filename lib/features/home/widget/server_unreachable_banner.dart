import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Попередження «сервер не відповідає» з кнопкою від'єднання.
///
/// Ядро піднімає тунель, не питаючи, чи живий сервер: інтерфейс створюється в
/// будь-якому разі, і застосунок чесно пише «Подключено». А оскільки весь
/// трафік телефона відтоді йде в тунель, при мертвому сервері людина лишається
/// взагалі без інтернету — і без жодного натяку на причину. Для тих, кому ми
/// роздаємо доступ, це виглядає як «зламався інтернет», а не «впав сервер», і
/// здогадатися вимкнути VPN вони не можуть.
///
/// Тому: почекавши, поки ядро встигне зміряти затримку, дивимось на результат.
/// Немає відповіді або таймаут — показуємо попередження й кнопку виходу.
class ServerUnreachableBanner extends HookConsumerWidget {
  const ServerUnreachableBanner({super.key});

  /// Скільки чекати після підключення, перш ніж робити висновки. Перша перевірка
  /// затримки доходить не миттєво, і лякати людину раніше часу не варто.
  static const _gracePeriod = Duration(seconds: 8);

  /// Понад це значення ядро вважає перевірку невдалою (те саме число вживається
  /// в індикаторі затримки).
  static const _timeoutDelay = 65000;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final connection = ref.watch(connectionNotifierProvider).valueOrNull;
    final connected = connection is Connected;

    final gracePassed = useState(false);
    useEffect(() {
      if (!connected) {
        gracePassed.value = false;
        return null;
      }
      final timer = Timer(_gracePeriod, () => gracePassed.value = true);
      return timer.cancel;
    }, [connected]);

    if (!connected || !gracePassed.value) return const SizedBox.shrink();

    final delay = ref.watch(activeProxyNotifierProvider).valueOrNull?.urlTestDelay ?? 0;
    final unreachable = delay <= 0 || delay >= _timeoutDelay;
    if (!unreachable) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Сервер не отвечает',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error),
          ),
          const Gap(4),
          Text(
            'Соединение поднято, но ответа нет — интернет через него не пойдёт. '
            'Отключитесь и попробуйте позже.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const Gap(8),
          FilledButton.tonal(
            onPressed: () => ref.read(connectionNotifierProvider.notifier).toggleConnection(),
            child: const Text('Отключить'),
          ),
        ],
      ),
    );
  }
}
