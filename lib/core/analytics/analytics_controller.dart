import 'package:hiddify/core/logger/logger_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'analytics_controller.g.dart';

const String enableAnalyticsPrefKey = "enable_analytics";

@Riverpod(keepAlive: true)
class AnalyticsController extends _$AnalyticsController with AppLogger {
  // «Лампа» не збирає аналітику взагалі. В оригіналі прапорець типово стояв у
  // true, і кожен встановлений застосунок слав звіти та трасування у Sentry
  // Hiddify — чужий проєкт, до якого ми не маємо стосунку. Повертаємо false
  // безумовно, щоб SentryFlutter не ініціалізувався навіть у тих, у кого в
  // shared_preferences лишилося старе значення.
  @override
  Future<bool> build() async {
    return false;
  }

  SharedPreferences get _preferences => ref.read(sharedPreferencesProvider).requireValue;

  /// Навмисно порожній: вмикати збір нема куди. Метод лишається, бо на нього
  /// посилається bootstrap і екран налаштувань в upstream.
  Future<void> enableAnalytics() async {}

  /// Прибирає прапорець, якщо він лишився від попередніх версій, і глушить
  /// Sentry на випадок, якщо його встиг підняти якийсь інший шлях.
  Future<void> disableAnalytics() async {
    loggy.debug("аналітика вимкнена назавжди");
    await _preferences.remove(enableAnalyticsPrefKey);
    await Sentry.close();
    LoggerController.instance.removePrinter("analytics");
    state = const AsyncData(false);
  }
}
