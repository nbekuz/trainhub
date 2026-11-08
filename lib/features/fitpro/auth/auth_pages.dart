import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/core/utils/ru_phone.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';
import 'package:trainhub/features/fitpro/session.dart';
import 'package:trainhub/features/fitpro/widgets/fit_widgets.dart';
import 'package:trainhub/routes/route_names.dart';

const _googleServerClientId = '179832539127-li3iqnnlln9oo160s38lsn34q0j9hsrk.apps.googleusercontent.com';

void _openHome(BuildContext context, FitUser user) {
  if (!user.profileComplete) {
    context.go(RouteNames.profileSetup);
    return;
  }
  context.go(user.role == FitRole.trainer ? RouteNames.trainer : RouteNames.client);
}

void _showError(BuildContext context, Object error) {
  Toast.error(FitApi.messageOf(error));
}

Future<void> _enterWithGoogle(WidgetRef ref, BuildContext context) async {
  final role = ref.read(fitSessionProvider).pendingRole ?? FitRole.client;
  try {
    final account = await GoogleSignIn(
      scopes: const ['email'],
      serverClientId: _googleServerClientId,
    ).signIn();
    final idToken = (await account?.authentication)?.idToken;
    if (idToken == null || idToken.isEmpty) return;
    final user = await FitApi.google(idToken: idToken, role: role);
    ref.read(fitSessionProvider.notifier).signIn(user);
    if (context.mounted) _openHome(context, user);
  } catch (error) {
    if (context.mounted) _showError(context, error);
  }
}

Future<void> _enterWithApple(WidgetRef ref, BuildContext context) async {
  final role = ref.read(fitSessionProvider).pendingRole ?? FitRole.client;
  try {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
    );
    final token = credential.identityToken;
    if (token == null || token.isEmpty) return;
    if (!context.mounted) return;
    final user = await FitApi.apple(
      identityToken: token,
      role: role,
      firstName: credential.givenName,
      lastName: credential.familyName,
    );
    ref.read(fitSessionProvider.notifier).signIn(user);
    if (context.mounted) _openHome(context, user);
  } catch (error) {
    if (context.mounted) _showError(context, error);
  }
}

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _controller = PageController();
  int _index = 0;

  static const _slides = [
    (
      'Индивидуальные\nтренировки',
      'Получайте персонализированные планы тренировок, созданные специально для вас и ваших целей.',
      'assets/images/onboarding_1_nobg.png',
    ),
    (
      'Отслеживание\nпрогресса',
      'Следите за своими достижениями, весом и показателями. Каждый шаг фиксируется для лучшего результата.',
      'assets/images/onboarding_2_nobg.png',
    ),
    (
      'Удобные\nинструменты',
      'Дневник тренировок, таймер, замеры тела и история занятий — в одном приложении. Тренируйтесь с комфортом.',
      'assets/images/onboarding_3_nobg.png',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _slides.length - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
    } else {
      context.push(RouteNames.role);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _slides.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, index) {
              final slide = _slides[index];
              return Padding(
                padding: const EdgeInsets.fromLTRB(28, 72, 28, 220),
                child: Column(
                  children: [
                    Expanded(
                      child: Image.asset(slide.$3, fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      slide.$1,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 32, height: 1.2, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      slide.$2,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16, height: 1.4),
                    ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            top: 8,
            right: 16,
            child: TextButton(
              onPressed: () => context.push(RouteNames.role),
              child: Text('Пропустить', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 18, fontWeight: FontWeight.w600)),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 28,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_slides.length, (i) {
                    final active = i == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      height: 10,
                      width: active ? 30 : 10,
                      decoration: BoxDecoration(
                        color: active ? AppColors.accent : Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 28),
                FitAccentButton(title: _index == _slides.length - 1 ? 'Начать' : 'Далее', onPressed: _next),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.push(RouteNames.login),
                  child: const Text.rich(
                    TextSpan(
                      text: 'Уже есть аккаунт? ',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                      children: [
                        TextSpan(text: 'Войти', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RolePage extends ConsumerStatefulWidget {
  const RolePage({super.key});

  @override
  ConsumerState<RolePage> createState() => _RolePageState();
}

class _RolePageState extends ConsumerState<RolePage> {
  FitRole? _role;

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Кто вы?', style: TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text('Выберите вашу роль для продолжения регистрации', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14)),
          const SizedBox(height: 56),
          _RoleCard(
            title: 'Тренер',
            subtitle: 'Я управляю\nтренировками клиентов',
            selected: _role == FitRole.trainer,
            image: _role == FitRole.trainer ? 'assets/images/trainer2.png' : 'assets/images/trainer1.png',
            onTap: () => setState(() => _role = FitRole.trainer),
          ),
          const SizedBox(height: 56),
          _RoleCard(
            title: 'Клиент',
            subtitle: 'Я хочу тренироваться\nи следить за прогрессом',
            selected: _role == FitRole.client,
            image: _role == FitRole.client ? 'assets/images/client2.png' : 'assets/images/client1.png',
            onTap: () => setState(() => _role = FitRole.client),
          ),
          const Spacer(),
          FitAccentButton(
            title: 'Продолжить',
            onPressed: _role == null
                ? null
                : () {
                    ref.read(fitSessionProvider.notifier).setPending(email: '', role: _role);
                    context.push(RouteNames.register);
                  },
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.image,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final String image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.black : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 190,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.fitMuted,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              right: 0,
              bottom: 0,
              top: 0,
              child: Image.asset(image, fit: BoxFit.fitHeight, alignment: Alignment.bottomRight),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selected) const Icon(Icons.check_circle, color: Colors.black, size: 24),
                  const Spacer(),
                  Text(title, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: color.withValues(alpha: 0.9), fontSize: 12, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _valid = false;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _check() {
    setState(() => _valid = _email.text.trim().length >= 3 && _password.text.isNotEmpty);
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final user = await FitApi.login(login: _email.text.trim(), password: _password.text);
      ref.read(fitSessionProvider.notifier).signIn(user);
      if (mounted) _openHome(context, user);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FitScaffold(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 36),
          const FitLogo(),
          const SizedBox(height: 36),
          const Text('Войти в аккаунт', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          FitField(
            label: 'Email или телефон',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => _check(),
          ),
          const SizedBox(height: 12),
          FitField(
            label: 'Пароль',
            controller: _password,
            obscureText: true,
            onChanged: (_) => _check(),
          ),
          const SizedBox(height: 16),
          FitAccentButton(
            title: 'Войти',
            loading: _loading,
            onPressed: _valid ? _submit : null,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.push(RouteNames.register),
            child: const Text.rich(
              TextSpan(
                text: 'Нет аккаунта? ',
                style: TextStyle(color: Colors.grey),
                children: [TextSpan(text: 'Регистрация', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700))],
              ),
            ),
          ),
          const Spacer(),
          const Text('или', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          if (defaultTargetPlatform != TargetPlatform.android) ...[
            FitSocialButton.apple(onPressed: () => _enterWithApple(ref, context)),
            const SizedBox(height: 12),
          ],
          FitSocialButton.google(onPressed: () => _enterWithGoogle(ref, context)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _name = TextEditingController();
  final _surname = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _valid = false;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _surname.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _check() {
    final emailOk = _email.text.contains('@') && _email.text.contains('.');
    setState(() {
      _valid = _name.text.trim().isNotEmpty && _surname.text.trim().isNotEmpty && emailOk && _password.text.length >= 8;
    });
  }

  Future<void> _submit() async {
    final role = ref.read(fitSessionProvider).pendingRole ?? FitRole.client;
    setState(() => _loading = true);
    try {
      final user = await FitApi.register(
        firstName: capitalizeWords(_name.text.trim()),
        lastName: capitalizeWords(_surname.text.trim()),
        email: _email.text.trim(),
        password: _password.text,
        role: role,
      );
      ref.read(fitSessionProvider.notifier).signIn(user);
      if (mounted) _openHome(context, user);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _valid;
    return FitScaffold(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          const SizedBox(height: 36),
          const FitLogo(),
          const SizedBox(height: 36),
          const Text('Зарегистрироваться', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          FitField(
            label: 'Имя',
            controller: _name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => _check(),
          ),
          const SizedBox(height: 12),
          FitField(
            label: 'Фамилия',
            controller: _surname,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => _check(),
          ),
          const SizedBox(height: 12),
          FitField(
            label: 'Email',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => _check(),
          ),
          const SizedBox(height: 12),
          FitField(
            label: 'Пароль',
            controller: _password,
            obscureText: true,
            onChanged: (_) => _check(),
          ),
          const SizedBox(height: 16),
          FitAccentButton(
            title: 'Зарегистрироваться',
            loading: _loading,
            onPressed: ready ? _submit : null,
          ),
          TextButton(
            onPressed: () => context.push(RouteNames.login),
            child: const Text.rich(
              TextSpan(
                text: 'Уже есть аккаунт? ',
                style: TextStyle(color: Colors.grey),
                children: [TextSpan(text: 'Войти', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700))],
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Center(child: Text('или', style: TextStyle(color: Colors.grey))),
          const SizedBox(height: 16),
          if (defaultTargetPlatform != TargetPlatform.android) ...[
            FitSocialButton.apple(onPressed: () => _enterWithApple(ref, context)),
            const SizedBox(height: 12),
          ],
          FitSocialButton.google(onPressed: () => _enterWithGoogle(ref, context)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class ProfileSetupPage extends ConsumerStatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  ConsumerState<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends ConsumerState<ProfileSetupPage> {
  final _phone = TextEditingController(text: RuPhone.formatDisplay(null));
  final _height = TextEditingController();
  final _weight = TextEditingController();
  String? _gender;
  DateTime? _birth;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(fitSessionProvider).user?.phone;
    if (existing != null && RuPhone.nationalDigits(existing).length >= 10) {
      _phone.text = RuPhone.formatDisplay(existing);
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  bool get _ready {
    final height = double.tryParse(_height.text.trim().replaceAll(',', '.'));
    final weight = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    final phoneOk = RuPhone.nationalDigits(_phone.text).length >= 10;
    return phoneOk &&
        _gender != null &&
        _birth != null &&
        height != null &&
        height >= 100 &&
        height <= 250 &&
        weight != null &&
        weight >= 30 &&
        weight <= 300;
  }

  Future<void> _pickBirth() async {
    final picked = await showBirthDateWheel(context, initial: _birth, minAge: 12);
    if (picked != null) setState(() => _birth = picked);
  }

  Future<void> _submit() async {
    final phoneApi = RuPhone.toApi(_phone.text);
    if (phoneApi == null) {
      Toast.error('Укажите телефон');
      return;
    }
    final birth = _birth!;
    final height = double.parse(_height.text.trim().replaceAll(',', '.'));
    final weight = double.parse(_weight.text.trim().replaceAll(',', '.'));
    final birthDate = '${birth.year}-${birth.month.toString().padLeft(2, '0')}-${birth.day.toString().padLeft(2, '0')}';
    setState(() => _loading = true);
    try {
      final user = await FitApi.patchMe(
        phone: phoneApi,
        gender: _gender,
        birthDate: birthDate,
        heightCm: height,
        weightGoalKg: weight,
      );
      ref.read(fitSessionProvider.notifier).signIn(user);
      if (mounted) _openHome(context, user);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: FitScaffold(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ListView(
                children: [
                  const Text(
                    'О вас',
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, height: 1.15),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Укажите телефон, пол, дату рождения, рост и целевой вес. Без этих данных профиль не откроется.',
                    style: TextStyle(color: AppColors.fitGrey, fontSize: 14, height: 1.45),
                  ),
                  const SizedBox(height: 28),
                  FitField(
                    label: 'Телефон',
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: const [RuPhoneInputFormatter()],
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 20),
                  const Text('Пол', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _GenderChip(
                        label: 'Мужской',
                        male: true,
                        selected: _gender == 'male',
                        onTap: () => setState(() => _gender = 'male'),
                      ),
                      const SizedBox(width: 12),
                      _GenderChip(
                        label: 'Женский',
                        male: false,
                        selected: _gender == 'female',
                        onTap: () => setState(() => _gender = 'female'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _BirthField(
                    value: _birth == null ? null : formatBirthDate(_birth!),
                    onTap: _pickBirth,
                  ),
                  const SizedBox(height: 14),
                  FitField(
                    label: 'Рост, см',
                    controller: _height,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_DecimalTextInputFormatter(maxDigits: 3)],
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  FitField(
                    label: 'Целевой вес, кг',
                    controller: _weight,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_DecimalTextInputFormatter(maxDigits: 3)],
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
            FitAccentButton(title: 'Продолжить', loading: _loading, onPressed: _ready ? _submit : null),
            SizedBox(height: MediaQuery.paddingOf(context).bottom > 0 ? 4 : 8),
          ],
        ),
      ),
    );
  }
}

class _BirthField extends StatelessWidget {
  const _BirthField({required this.onTap, this.value});

  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: InputDecorator(
        isEmpty: !hasValue,
        decoration: InputDecoration(
          labelText: 'Дата рождения',
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: const TextStyle(color: AppColors.fitGrey, fontSize: 12),
          floatingLabelStyle: const TextStyle(color: AppColors.fitGrey, fontSize: 12),
          filled: true,
          fillColor: const Color(0xFF232323),
          contentPadding: const EdgeInsets.fromLTRB(18, 20, 12, 16),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 14),
            child: SvgPicture.string(
              _calendarIcon,
              width: 22,
              height: 22,
              colorFilter: const ColorFilter.mode(AppColors.accent, BlendMode.srcIn),
            ),
          ),
          suffixIconConstraints: const BoxConstraints(minWidth: 46, minHeight: 22),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF323232)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
          ),
        ),
        child: Text(
          hasValue ? value! : 'ДД.ММ.ГГГГ',
          style: TextStyle(
            color: hasValue ? Colors.white : AppColors.fitGrey,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _DecimalTextInputFormatter extends TextInputFormatter {
  const _DecimalTextInputFormatter({required this.maxDigits});

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(',', '.');
    if (text.isEmpty) {
      return newValue.copyWith(text: text, selection: const TextSelection.collapsed(offset: 0));
    }
    final pattern = RegExp('^\\d{0,$maxDigits}(\\.\\d{0,1})?\$');
    if (!pattern.hasMatch(text)) return oldValue;
    return newValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length.clamp(0, text.length)),
    );
  }
}

class _GenderChip extends StatelessWidget {
  const _GenderChip({required this.label, required this.male, required this.selected, required this.onTap});

  final String label;
  final bool male;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.black : Colors.white;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : const Color(0xFF232323),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? AppColors.accent : const Color(0xFF323232)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.string(
                  male ? _maleIcon : _femaleIcon,
                  width: 18,
                  height: 18,
                  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                ),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _calendarIcon = '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M8 2V5M16 2V5M3.5 9.09H20.5M21 8.5V17C21 20 19.5 22 16 22H8C4.5 22 3 20 3 17V8.5C3 5.5 4.5 3.5 8 3.5H16C19.5 3.5 21 5.5 21 8.5Z" stroke="white" stroke-width="1.5" stroke-miterlimit="10" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M15.695 13.7H15.704M15.695 16.7H15.704M11.995 13.7H12.005M11.995 16.7H12.005M8.294 13.7H8.304M8.294 16.7H8.304" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';

const _maleIcon = '''
<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M9.5 2.5H13.5V6.5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M13.5 2.5L8.8 7.2" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
<circle cx="6" cy="10" r="3.25" stroke="currentColor" stroke-width="1.5"/>
</svg>
''';

const _femaleIcon = '''
<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
<circle cx="8" cy="5.75" r="3.25" stroke="currentColor" stroke-width="1.5"/>
<path d="M8 9V14M5.75 11.75H10.25" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
</svg>
''';

class OtpPage extends ConsumerStatefulWidget {
  const OtpPage({super.key});

  @override
  ConsumerState<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends ConsumerState<OtpPage> {
  final _controllers = List.generate(4, (_) => TextEditingController());
  final _nodes = List.generate(4, (_) => FocusNode());
  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  bool get _complete => _controllers.every((c) => c.text.length == 1);

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(fitSessionProvider).pendingEmail;
    return FitScaffold(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.chevron_left, color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(height: 12),
          const FitLogo(),
          const SizedBox(height: 28),
          const Text('Введите код из Email', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Мы отправили вам письмо с кодом подтверждения на $email. Введите его ниже, чтобы подтвердить ваш аккаунт.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              return Container(
                width: 72,
                height: 72,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppColors.fitBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.fitBorder),
                ),
                child: TextField(
                  controller: _controllers[index],
                  focusNode: _nodes[index],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                  onChanged: (value) {
                    if (value.isNotEmpty && index < 3) _nodes[index + 1].requestFocus();
                    if (value.isEmpty && index > 0) _nodes[index - 1].requestFocus();
                    setState(() {});
                  },
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          FitAccentButton(
            title: 'Продолжить',
            onPressed: _complete
                ? () {
                    final session = ref.read(fitSessionProvider);
                    final role = session.pendingRole ?? FitRole.client;
                    final parts = session.pendingName.trim().split(RegExp(r'\s+'));
                    final user = FitUser(
                      id: 1,
                      name: parts.isEmpty || parts.first.isEmpty ? 'Вадим' : parts.first,
                      surname: parts.length > 1 ? parts.sublist(1).join(' ') : '',
                      email: session.pendingEmail,
                      uuid: '45069230',
                      role: role,
                    );
                    ref.read(fitSessionProvider.notifier).signIn(user);
                    context.go(role == FitRole.trainer ? RouteNames.trainer : RouteNames.client);
                  }
                : null,
          ),
          const SizedBox(height: 12),
          const Text.rich(
            TextSpan(
              text: 'Не пришло письмо? ',
              style: TextStyle(color: Colors.white),
              children: [TextSpan(text: 'Отправить повторно', style: TextStyle(color: AppColors.accent))],
            ),
          ),
        ],
      ),
    );
  }
}
