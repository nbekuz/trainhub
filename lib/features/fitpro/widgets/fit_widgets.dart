import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';

/// Exercise art is a transparent HQ PNG on a white circular plate (Figma thumb).
class FitExerciseThumb extends StatelessWidget {
  const FitExerciseThumb({
    super.key,
    this.url,
    this.size = 48,
    this.padding,
  });

  /// Accepts raw API path or absolute URL; resolved via [FitMedia.url].
  final String? url;
  final double size;
  /// Inset so the figure sits inside the white circle without cropping.
  final double? padding;

  factory FitExerciseThumb.fromExercise(Map<String, dynamic> item, {Key? key, double size = 48}) {
    return FitExerciseThumb(key: key, url: FitMedia.exercisePhoto(item), size: size);
  }

  @override
  Widget build(BuildContext context) {
    final resolved = FitMedia.url(url);
    // Slightly tighter inset — HQ assets are full-figure with transparent bg.
    final inset = padding ?? (size * 0.08).clamp(3.0, 8.0);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (size * dpr * 2).round().clamp(96, 512);
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: resolved == null
          ? Icon(Icons.fitness_center, color: Colors.black45, size: size * 0.42)
          : Padding(
              padding: EdgeInsets.all(inset),
              child: Image.network(
                resolved,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                // Only cacheWidth — setting both W+H to a square distorts aspect ratio.
                cacheWidth: cachePx,
                errorBuilder: (_, _, _) => Icon(Icons.fitness_center, color: Colors.black45, size: size * 0.42),
              ),
            ),
    );
  }
}

/// Figma sheet backdrop: blur + dim (#232323 @ 50%) behind the panel.
Future<T?> showBlurredModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool enableDrag = true,
  Color sheetColor = const Color(0xFF232323),
  BorderRadiusGeometry borderRadius = const BorderRadius.vertical(top: Radius.circular(24)),
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    builder: (ctx) {
      return SizedBox(
        height: MediaQuery.sizeOf(ctx).height,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(ctx).maybePop(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: const ColoredBox(color: Color(0x59232323)),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                color: sheetColor,
                borderRadius: borderRadius,
                clipBehavior: Clip.antiAlias,
                child: builder(ctx),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class FitScaffold extends StatelessWidget {
  const FitScaffold({
    super.key,
    required this.child,
    this.padding,
    this.onRefresh,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  /// Pull-to-refresh: re-run GET APIs. Child should be a scrollable
  /// (ListView/CustomScrollView) with [AlwaysScrollableScrollPhysics] when short.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    Widget body = Padding(padding: padding ?? EdgeInsets.zero, child: child);
    if (onRefresh != null) {
      body = RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: const Color(0xFF232323),
        displacement: 40,
        onRefresh: onRefresh!,
        child: body,
      );
    }
    return Scaffold(
      backgroundColor: AppColors.fitBg,
      body: SafeArea(
        bottom: false,
        child: body,
      ),
    );
  }
}

/// Scroll physics that always allows overscroll so [RefreshIndicator] works
/// even when content is shorter than the viewport.
const fitAlwaysScroll = AlwaysScrollableScrollPhysics();

class FitLogo extends StatelessWidget {
  const FitLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/images/logo.png', width: 240, fit: BoxFit.contain);
  }
}

class FitAccentButton extends StatelessWidget {
  const FitAccentButton({
    super.key,
    required this.title,
    required this.onPressed,
    this.loading = false,
  });

  final String title;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return SizedBox(
      height: 64,
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: enabled ? AppColors.accent : AppColors.fitMuted,
          disabledBackgroundColor: AppColors.fitMuted,
          foregroundColor: enabled ? Colors.black : Colors.white,
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(title),
      ),
    );
  }
}

/// Apple-style day / month / year wheel. Returns the chosen date, or null if dismissed.
Future<DateTime?> showBirthDateWheel(BuildContext context, {DateTime? initial, int minAge = 0, int maxAge = 100}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final minimum = _dateYearsAgo(today, maxAge);
  final maximum = minAge <= 0 ? today : _dateYearsAgo(today, minAge);
  var selected = initial ?? DateTime(1995, 6, 15);
  if (selected.isBefore(minimum)) selected = minimum;
  if (selected.isAfter(maximum)) selected = maximum;
  selected = DateTime(selected.year, selected.month, selected.day);

  return showCupertinoModalPopup<DateTime>(
    context: context,
    barrierColor: const Color(0x80232323),
    builder: (context) {
      return Container(
        height: 320,
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1C),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отмена', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16)),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: () => Navigator.pop(context, selected),
                    child: const Text('Готово', style: TextStyle(color: Color(0xFFC7F137), fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoTheme(
                data: const CupertinoThemeData(
                  brightness: Brightness.dark,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(color: Colors.white, fontSize: 21),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: selected,
                  minimumDate: minimum,
                  maximumDate: maximum,
                  onDateTimeChanged: (value) => selected = DateTime(value.year, value.month, value.day),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Minutes / seconds wheel (up to 59:59). Returns the chosen duration, or null if dismissed.
Future<Duration?> showTimerDurationWheel(BuildContext context, {Duration initial = const Duration(minutes: 3)}) {
  var selected = initial > const Duration(minutes: 59, seconds: 59) ? const Duration(minutes: 59, seconds: 59) : initial;
  return showCupertinoModalPopup<Duration>(
    context: context,
    barrierColor: const Color(0x80232323),
    builder: (context) {
      return Container(
        height: 320,
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1C),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отмена', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16)),
                  ),
                  const Expanded(
                    child: Text(
                      'Время таймера',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: () => Navigator.pop(context, selected),
                    child: const Text('Готово', style: TextStyle(color: Color(0xFFC7F137), fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoTheme(
                data: const CupertinoThemeData(
                  brightness: Brightness.dark,
                  textTheme: CupertinoTextThemeData(
                    pickerTextStyle: TextStyle(color: Colors.white, fontSize: 21),
                  ),
                ),
                child: CupertinoTimerPicker(
                  mode: CupertinoTimerPickerMode.ms,
                  initialTimerDuration: selected,
                  onTimerDurationChanged: (value) => selected = value,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

String formatBirthDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day.$month.${date.year}';
}

DateTime _dateYearsAgo(DateTime from, int years) {
  final year = from.year - years;
  final lastDay = DateTime(year, from.month + 1, 0).day;
  return DateTime(year, from.month, from.day > lastDay ? lastDay : from.day);
}

/// `nodir najmiddinov` → `Nodir Najmiddinov`, `анна-мария` → `Анна-Мария`.
/// Only the first letter of each word changes; letters whose upper case has a
/// different length (e.g. `ß`) are kept so cursor offsets stay valid.
String capitalizeWords(String text) {
  if (text.isEmpty) return text;
  final buffer = StringBuffer();
  var atWordStart = true;
  for (final ch in text.characters) {
    if (atWordStart) {
      final upper = ch.toUpperCase();
      buffer.write(upper.length == ch.length ? upper : ch);
    } else {
      buffer.write(ch);
    }
    atWordStart = ch.trim().isEmpty || ch == '-';
  }
  return buffer.toString();
}

/// Upper-cases the first letter of every word (names), even for pasted text.
class CapitalizeWordsFormatter extends TextInputFormatter {
  const CapitalizeWordsFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Don't touch text an IME is still composing (CJK, etc.).
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) return newValue;
    final next = capitalizeWords(newValue.text);
    if (next == newValue.text) return newValue;
    return newValue.copyWith(text: next);
  }
}

class FitField extends StatelessWidget {
  const FitField({
    super.key,
    required this.label,
    required this.controller,
    this.keyboardType,
    this.onChanged,
    this.obscureText = false,
    this.prefix,
    this.inputFormatters,
    this.autofillHints,
    this.enableSuggestions = true,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final Widget? prefix;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final bool enableSuggestions;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final isEmail = keyboardType == TextInputType.emailAddress;
    final suggestions = enableSuggestions && !isEmail;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      obscureText: obscureText,
      inputFormatters: !isEmail && textCapitalization == TextCapitalization.words
          ? [...?inputFormatters, const CapitalizeWordsFormatter()]
          : inputFormatters,
      autofillHints: autofillHints,
      enableSuggestions: suggestions,
      autocorrect: suggestions,
      smartDashesType: isEmail ? SmartDashesType.disabled : null,
      smartQuotesType: isEmail ? SmartQuotesType.disabled : null,
      textCapitalization: isEmail ? TextCapitalization.none : textCapitalization,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.fitGrey, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: AppColors.fitGrey, fontSize: 12),
        prefixIcon: prefix == null
            ? null
            : Padding(padding: const EdgeInsets.only(left: 14, right: 10), child: prefix),
        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 16),
        filled: true,
        fillColor: const Color(0xFF232323),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFF323232)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
        ),
      ),
    );
  }
}

class FitSocialButton extends StatelessWidget {
  const FitSocialButton.apple({super.key, this.onPressed})
      : title = 'Продолжить с Apple',
        asset = 'assets/icons/social/apple.svg';

  const FitSocialButton.google({super.key, this.onPressed})
      : title = 'Продолжить с Google',
        asset = 'assets/icons/social/google.svg';

  final String title;
  final String asset;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(asset, width: 20, height: 20),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(color: Color(0xFF333333), fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class FitPageTitle extends StatelessWidget {
  const FitPageTitle({super.key, required this.title, this.trailing, this.leading});

  final String title;
  final Widget? trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    if (leading == null && trailing == null) {
      return SizedBox(
        height: 56,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
        ),
      );
    }

    return SizedBox(
      height: 56,
      child: Row(
        children: [
          if (leading != null) leading! else const SizedBox(width: 48),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          if (trailing != null) trailing! else const SizedBox(width: 48),
        ],
      ),
    );
  }
}
