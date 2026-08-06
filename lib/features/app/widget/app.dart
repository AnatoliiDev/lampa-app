import 'package:accessibility_tools/accessibility_tools.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hiddify/core/localization/locale_extensions.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/app_update/notifier/app_update_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/connection/widget/connection_wrapper.dart';
import 'package:hiddify/features/per_app_proxy/overview/per_app_proxy_service_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/home/widget/overlay_permission_card.dart';
import 'package:hiddify/features/home/widget/revoked_access_banner.dart';
import 'package:hiddify/features/proxy/active/prefer_lowest_delay.dart';
import 'package:hiddify/features/shortcut/shortcut_wrapper.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/features/window/widget/window_wrapper.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:toastification/toastification.dart';
import 'package:upgrader/upgrader.dart';

bool _debugAccessibility = false;
bool isOnPauseCalled = false;

class App extends HookConsumerWidget with WidgetsBindingObserver, PresLogger {
  const App({super.key});

  void onInactive(WidgetRef ref) {
    onPause(ref);
  }

  void onPause(WidgetRef ref) {
    if (PlatformUtils.isDesktop) return;
    isOnPauseCalled = true;
    ref.read(hiddifyCoreServiceProvider).closeFront();
  }

  void onResume(WidgetRef ref) {
    // if (PlatformUtils.isDesktop) return;

    // Ядро піднімаємо заново лише тоді, коли підключення не в процесі.
    //
    // Перше підключення на новому пристрої йде так: Android показує своє вікно
    // згоди на VPN, застосунок при цьому згортається, а після «ОК» —
    // повертається. Повернення тягло за собою перезапуск ядра просто посеред
    // підключення: потік, що чекав на стан, лишався з мертвим каналом і чесно
    // чекав у порожнечу, а людина за півхвилини бачила «startService». Саме це
    // й ловив кожен, хто ставив застосунок уперше.
    final status = ref.read(connectionNotifierProvider).valueOrNull;
    if (status is! Connecting && status is! Disconnecting) {
      ref.read(hiddifyCoreServiceProvider).init();
    }
    // Поки застосунок був згорнутий, доступ могли забрати — і служба вже
    // вимкнула тунель. Без цього рядка людина повертається й бачить звичайну
    // кнопку «Подключить», ніби нічого не сталося.
    ref.invalidate(accessStateProvider);
    // Людина щойно могла ввімкнути дозвіл на вікна поверх інших застосунків —
    // вона поверталася саме з того екрана. Без перепитування картка з проханням
    // висіла б далі, ніби нічого не сталося.
    ref.invalidate(canDrawOverlaysProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isOnPauseCalled && PlatformUtils.isAndroid) ref.invalidate(perAppProxyServiceProvider);
      isOnPauseCalled = false;
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    setupStateListener(ref);
    final router = ref.watch(goRouterNotiferProvider);
    final locale = ref.watch(localePreferencesProvider);
    final themeMode = ref.watch(themePreferencesProvider);
    final theme = AppTheme(themeMode, locale.preferredFontFamily);
    final upgrader = ref.watch(upgraderProvider);
    final activeBreakpoint = Breakpoint(context).activeBreakpoint;

    ref.listen(foregroundProfilesUpdateNotifierProvider, (_, _) {});
    // Після кожного підключення ставимо канал із меншою затримкою замість
    // почергового, який ядро нав'язує типовим — див. preferLowestDelayProvider.
    ref.listen(preferLowestDelayProvider, (_, _) {});
    // Служба перевіряє доступ у фоні, але адресу підписки знає лише Dart.
    ref.listen(subscriptionUrlSyncProvider, (_, _) {});
    if (PlatformUtils.isAndroid) ref.listen(perAppProxyServiceProvider, (_, _) {});
    if (PlatformUtils.isDesktop) ref.listen(systemTrayNotifierProvider, (_, _) {});

    // updating ActiveBreakpointNotifier value
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeBreakpointNotifierProvider.notifier).update(activeBreakpoint);
      });
      return null;
    }, [activeBreakpoint]);
    return WindowWrapper(
      ShortcutWrapper(
        ToastificationWrapper(
          child: ConnectionWrapper(
            DynamicColorBuilder(
              builder: (ColorScheme? lightColorScheme, ColorScheme? darkColorScheme) {
                return MaterialApp.router(
                  routerConfig: router,
                  locale: locale.flutterLocale,
                  supportedLocales: AppLocaleUtils.supportedLocales,
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  debugShowCheckedModeBanner: false,
                  themeMode: themeMode.flutterThemeMode,
                  theme: theme.lightTheme(lightColorScheme),
                  darkTheme: theme.darkTheme(darkColorScheme),
                  title: Constants.appName,
                  builder: (context, child) {
                    final theme = Theme.of(context);
                    child = UpgradeAlert(
                      upgrader: upgrader,
                      navigatorKey: router.routerDelegate.navigatorKey,
                      child: child ?? const SizedBox(),
                    );
                    if (kDebugMode && _debugAccessibility) {
                      return AccessibilityTools(checkFontOverflows: true, child: child);
                    }
                    return AnnotatedRegion<SystemUiOverlayStyle>(
                      value: SystemUiOverlayStyle(
                        statusBarColor: theme.scaffoldBackgroundColor,
                        systemNavigationBarColor: theme.scaffoldBackgroundColor,
                        systemNavigationBarIconBrightness: theme.brightness == Brightness.dark
                            ? Brightness.light
                            : Brightness.dark,
                      ),
                      child: child,
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // @override
  // Widget build1(BuildContext context, WidgetRef ref) {
  //   setupStateListener(ref);
  //   // setupQuickSettings(ref);
  //   final router = ref.watch(routerProvider);
  //   final locale = ref.watch(localePreferencesProvider);
  //   final themeMode = ref.watch(themePreferencesProvider);
  //   final theme = AppTheme(themeMode, locale.preferredFontFamily);
  //   final upgrader = ref.watch(upgraderProvider);

  //   ref.listen(foregroundProfilesUpdateNotifierProvider, (_, __) {});

  //   return WindowWrapper(
  //     TrayWrapper(
  //       ShortcutWrapper(
  //         ConnectionWrapper(
  //           PlatformProvider(
  //               settings: PlatformSettingsData(
  //                 iosUsesMaterialWidgets: true,
  //               ),
  //               builder: (context) => DynamicColorBuilder(
  //                     builder: (ColorScheme? lightColorScheme, ColorScheme? darkColorScheme) {
  //                       return PlatformApp.router(
  //                         routerConfig: router,
  //                         locale: locale.flutterLocale,
  //                         supportedLocales: AppLocaleUtils.supportedLocales,
  //                         localizationsDelegates: GlobalMaterialLocalizations.delegates,
  //                         debugShowCheckedModeBanner: false,
  //                         material: (context, platform) => MaterialAppRouterData(
  //                           theme: theme.lightTheme(lightColorScheme),
  //                           darkTheme: theme.darkTheme(darkColorScheme),
  //                           themeMode: themeMode.flutterThemeMode,
  //                         ),
  //                         cupertino: (context, platform) {
  //                           final sysDark = MediaQuery.of(context).platformBrightness == Brightness.dark;

  //                           return CupertinoAppRouterData(theme: theme.cupertinoThemeData(sysDark, lightColorScheme, darkColorScheme));
  //                         },
  //                         title: Constants.appName,
  //                         builder: (context, child) {
  //                           child = UpgradeAlert(
  //                             upgrader: upgrader,
  //                             navigatorKey: router.routerDelegate.navigatorKey,
  //                             child: child ?? const SizedBox(),
  //                           );
  //                           if (kDebugMode && _debugAccessibility) {
  //                             return AccessibilityTools(
  //                               checkFontOverflows: true,
  //                               child: child,
  //                             );
  //                           }
  //                           return child;
  //                         },
  //                       );
  //                     },
  //                   )),
  //         ),
  //       ),
  //     ),
  //   );
  // }

  void setupStateListener(WidgetRef ref) {
    final appLifecycleState = useAppLifecycleState();

    useEffect(() {
      loggy.info("current app state");
      loggy.info(appLifecycleState);
      if (appLifecycleState == AppLifecycleState.paused) {
        onPause(ref);
      } else if (appLifecycleState == AppLifecycleState.inactive) {
        onInactive(ref);
      } else if (appLifecycleState == AppLifecycleState.resumed) {
        onResume(ref);
      }
      return null;
    }, [appLifecycleState]);
  }
}
