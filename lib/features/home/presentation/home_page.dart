import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trainhub/components/app_bar/app_app_bar.dart';
import 'package:trainhub/components/buttons/app_button.dart';
import 'package:trainhub/components/cards/app_card.dart';
import 'package:trainhub/components/inputs/app_text_field.dart';
import 'package:trainhub/components/loading/loading_overlay.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/constants/spacing.dart';
import 'package:trainhub/core/theme/theme_provider.dart';
import 'package:trainhub/core/utils/responsive.dart';
import 'package:trainhub/core/utils/validator.dart';

/// Demo home page showcasing template building blocks.
class HomePage extends ConsumerStatefulWidget {
  /// Creates the home page.
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _buttonLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _demoLoading() async {
    Loading.show(context, message: 'Please wait…');
    await Future<void>.delayed(const Duration(seconds: 2));
    Loading.hide();
    Toast.success('Loading finished');
  }

  Future<void> _demoSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      Toast.warning('Please fix the form errors');
      return;
    }
    setState(() => _buttonLoading = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _buttonLoading = false);
    Toast.success('Saved successfully');
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final maxWidth = Responsive.contentWidth(context);

    return Scaffold(
      appBar: AppAppBar(
        title: 'Home',
        actions: [
          AppButton.icon(
            icon: themeMode == ThemeMode.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
            children: [
              Text(
                'TrainHub',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Starter kit with Clean Architecture, Dio, Riverpod, GetIt and GoRouter.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Components playground',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppTextField(
                        controller: _emailController,
                        label: 'Email',
                        hint: 'you@example.com',
                        prefixIcon: Icons.mail_outline,
                        keyboardType: TextInputType.emailAddress,
                        validator: Validator.email,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppButton(
                        label: 'Submit',
                        expand: true,
                        isLoading: _buttonLoading,
                        onPressed: _demoSubmit,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppButton(
                        label: 'Outlined action',
                        expand: true,
                        variant: AppButtonVariant.outlined,
                        onPressed: () => Toast.info('Outlined pressed'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppButton(
                        label: 'Show loading',
                        expand: true,
                        variant: AppButtonVariant.text,
                        icon: Icons.hourglass_top_rounded,
                        onPressed: _demoLoading,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          AppButton(
                            label: 'Success',
                            onPressed: () => Toast.success('Saved successfully'),
                          ),
                          AppButton(
                            label: 'Error',
                            backgroundColor: Theme.of(context).colorScheme.error,
                            onPressed: () => Toast.error('Something went wrong'),
                          ),
                          AppButton(
                            label: 'Warning',
                            onPressed: () => Toast.warning('Be careful'),
                          ),
                          AppButton(
                            label: 'Info',
                            onPressed: () => Toast.info('Quick tip'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
