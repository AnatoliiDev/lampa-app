import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/invite/data/invite_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Приводить ввід до вигляду ABCD-EFGH: коди диктують голосом і переписують
/// з екрана, тому регістр і зайві символи виправляємо мовчки, а не лаємось.
class _InviteCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue _, TextEditingValue next) {
    final cleaned = next.text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    final limited = cleaned.length > 8 ? cleaned.substring(0, 8) : cleaned;
    final formatted = limited.length > 4 ? '${limited.substring(0, 4)}-${limited.substring(4)}' : limited;

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class InvitePage extends HookConsumerWidget with PresLogger {
  const InvitePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final controller = useTextEditingController();
    final code = useValueListenable(controller).text;
    final isBusy = useState(false);
    final error = useState<String?>(null);

    String messageFor(InviteFailure failure) => switch (failure) {
      InviteFailure.notFound => t.invite.errors.notFound,
      InviteFailure.alreadyUsed => t.invite.errors.used,
      InviteFailure.tooManyAttempts => t.invite.errors.tooMany,
      InviteFailure.network => t.invite.errors.network,
    };

    Future<void> submit() async {
      if (isBusy.value) return;
      isBusy.value = true;
      error.value = null;

      try {
        final url = await ref.read(inviteRepositoryProvider).redeem(code);

        await ref
            .read(addProfileNotifierProvider.notifier)
            .addManual(url: url, userOverride: const UserOverride(name: Constants.appName));

        // addManual ковтає помилки в стан замість того, щоб їх кидати.
        final result = ref.read(addProfileNotifierProvider);
        if (result.hasError) {
          loggy.warning("не вдалося додати профіль", result.error);
          error.value = t.invite.errors.network;
          return;
        }

        if (context.mounted) context.go('/home');
      } on InviteException catch (e) {
        error.value = messageFor(e.failure);
      } finally {
        isBusy.value = false;
      }
    }

    final canSubmit = code.length == 9 && !isBusy.value;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.invite.title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                  const Gap(8),
                  Text(
                    t.invite.subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const Gap(32),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: !isBusy.value,
                    style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 4),
                    inputFormatters: [_InviteCodeFormatter()],
                    decoration: InputDecoration(
                      hintText: t.invite.hint,
                      errorText: error.value,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => canSubmit ? submit() : null,
                  ),
                  const Gap(24),
                  FilledButton(
                    onPressed: canSubmit ? submit : null,
                    child: isBusy.value
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(t.invite.submit),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
