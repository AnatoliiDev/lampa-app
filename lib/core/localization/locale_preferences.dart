import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/gen/translations.g.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'locale_preferences.g.dart';

@Riverpod(keepAlive: true)
class LocalePreferences extends _$LocalePreferences with AppLogger {
  // Інтерфейс завжди російською — незалежно від локалі телефона й від того, що
  // лишилося в shared_preferences від попередніх версій. Вибору мови в
  // налаштуваннях немає, тож збережене значення читати нема сенсу: воно тільки
  // створило б розбіжність між тим, що людина бачить, і тим, що вона може
  // змінити. Коли з'явиться потреба в кількох мовах — сюди повертається читання
  // ключа "locale", а в general_page — LocalePrefTile.
  @override
  AppLocale build() => AppLocale.ru;

  Future<void> changeLocale(AppLocale value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).requireValue.setString("locale", value.name);
  }
}
