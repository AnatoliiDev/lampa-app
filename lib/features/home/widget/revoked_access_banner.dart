import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:fpdart/fpdart.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'revoked_access_banner.g.dart';

/// Чи відкликано доступ на сервері.
///
/// Коли доступ забирають в адмінці, застосунок про це не дізнається: профіль
/// уже лежить на пристрої, підключення просто перестає працювати. А ввести новий
/// код нема де — екран профілів на телефоні ми навмисно прибрали, щоб не плутати
/// людей. Виходив глухий кут, і саме в ньому опинявся б кожен, кому доступ
/// поновлюють.
///
/// Тому питаємо сервер напряму. Він розрізняє два випадки:
/// **404** — підписки немає, людину видалили, потрібен новий код;
/// **403** — доступ призупинено, код лишається чинним, досить увімкнути назад.
/// Мережеві негаразди до уваги не беремо — краще промовчати, ніж дарма лякати.
enum AccessState { ok, suspended, gone }

@riverpod
Future<AccessState> accessState(Ref ref) async {
  final profile = await ref.watch(activeProfileProvider.future);
  if (profile is! RemoteProfileEntity) return AccessState.ok;

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(Uri.parse(profile.url));
    final response = await request.close().timeout(const Duration(seconds: 10));
    await response.drain<void>();
    final state = switch (response.statusCode) {
      404 => AccessState.gone,
      403 => AccessState.suspended,
      _ => AccessState.ok,
    };
    // Поки доступ закритий — перепитуємо самі. Інакше людина сиділа б із
    // написом «приостановлен» ще довго після того, як її увімкнули назад:
    // перевірка робиться при відкритті застосунку й при втраті зв'язку, а
    // жодної з цих подій тут не станеться.
    if (state != AccessState.ok) _recheckLater(ref);
    return state;
  } catch (_) {
    return AccessState.ok;
  } finally {
    client.close(force: true);
  }
}

/// Крок перепитування, поки доступ закритий.
const _recheckEvery = Duration(seconds: 20);

void _recheckLater(Ref ref) {
  final timer = Timer(_recheckEvery, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
}

/// Повідомлення про відкликаний доступ і вихід із глухого кута.
class RevokedAccessBanner extends HookConsumerWidget with InfraLogger {
  const RevokedAccessBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(accessStateProvider).valueOrNull ?? AccessState.ok;
    final connected = ref.watch(connectionNotifierProvider).valueOrNull is Connected;

    // Доступу немає — виходимо з тунелю самі. Інакше телефон лишається взагалі
    // без інтернету: тунель на пристрої живий, а сервер уже не пускає, і весь
    // трафік іде в нікуди. Людина бачить «зламався інтернет» і не здогадується
    // натиснути «Відключити».
    useEffect(() {
      if (state != AccessState.ok && connected) {
        ref.read(connectionNotifierProvider.notifier).toggleConnection();
      }
      return null;
    }, [state, connected]);

    if (state == AccessState.ok) return const SizedBox.shrink();

    final gone = state == AccessState.gone;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            gone ? 'Доступ больше не действует' : 'Доступ приостановлен',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error),
          ),
          const Gap(4),
          Text(
            gone
                ? 'Попросите новый код у того, кто дал вам это приложение.'
                : 'Код остаётся действующим — доступ включат обратно, и всё заработает.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (gone) ...[
            const Gap(8),
            FilledButton.tonal(
              onPressed: () async {
                final profile = await ref.read(activeProfileProvider.future);
                if (profile == null) return;
                // Щойно профілів не лишиться, маршрутизатор сам поверне людину на
                // екран уведення коду — окремий перехід тут не потрібен.
                final repository = await ref.read(profileRepositoryProvider.future);
                await repository.deleteById(profile.id, profile.active).getOrElse((err) {
                  loggy.warning('не вдалося видалити відкликаний профіль', err);
                  return unit;
                }).run();
              },
              child: const Text('Ввести новый код'),
            ),
          ],
        ],
      ),
    );
  }
}
