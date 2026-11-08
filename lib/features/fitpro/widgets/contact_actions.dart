import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/core/utils/ru_phone.dart';
import 'package:url_launcher/url_launcher.dart';

/// Figma «Связаться»: phone (required to show) + optional WhatsApp / Telegram.
class ContactActionsRow extends StatelessWidget {
  const ContactActionsRow({
    super.key,
    required this.phone,
    this.whatsapp,
    this.telegram,
  });

  final String phone;
  final String? whatsapp;
  final String? telegram;

  static String? _digits(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final digits = RuPhone.digitsOnly(raw);
    return digits.isEmpty ? null : digits;
  }

  /// Telegram username only (`nbekdev` / `@nbekdev`), no phone.
  static String? _tgTarget(String? raw) {
    if (raw == null) return null;
    var text = raw.trim();
    if (text.isEmpty) return null;
    text = text.replaceFirst(RegExp(r'^https?://t\.me/'), '');
    text = text.replaceFirst(RegExp(r'^t\.me/'), '');
    text = text.split('?').first.split('/').first.trim();
    text = text.replaceFirst(RegExp(r'^@'), '');
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{4,31}$').hasMatch(text)) return null;
    return text;
  }

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) Toast.error('Не удалось открыть приложение');
  }

  Future<void> _call() async {
    final digits = _digits(phone);
    if (digits == null) {
      Toast.info('Телефон не указан');
      return;
    }
    await _open(Uri(scheme: 'tel', path: '+$digits'));
  }

  Future<void> _wa() async {
    final digits = _digits(whatsapp);
    if (digits == null) return;
    await _open(Uri.parse('https://wa.me/$digits'));
  }

  Future<void> _tg() async {
    final target = _tgTarget(telegram);
    if (target == null) return;
    await _open(Uri.parse('https://t.me/$target'));
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = (_digits(phone) ?? '').length >= 10;
    final hasWa = (_digits(whatsapp) ?? '').length >= 10;
    final hasTg = _tgTarget(telegram) != null;
    final display = hasPhone ? RuPhone.formatDisplay(phone) : 'Нет телефона';

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: hasPhone ? _call : null,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: hasPhone ? AppColors.accent : const Color(0xFF3A3A3A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/icons/contact/phone.svg',
                    width: 18,
                    height: 18,
                    colorFilter: ColorFilter.mode(
                      hasPhone ? Colors.black : AppColors.fitGrey,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      display,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasPhone ? Colors.black : AppColors.fitGrey,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (hasWa) ...[
          const SizedBox(width: 8),
          _ContactIconButton(
            asset: 'assets/icons/contact/whatsapp.svg',
            onTap: _wa,
          ),
        ],
        if (hasTg) ...[
          const SizedBox(width: 8),
          _ContactIconButton(
            asset: 'assets/icons/contact/telegram.svg',
            onTap: _tg,
          ),
        ],
      ],
    );
  }
}

class _ContactIconButton extends StatelessWidget {
  const _ContactIconButton({required this.asset, required this.onTap});

  final String asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        width: 76,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF323232)),
        ),
        child: SvgPicture.asset(asset, width: 24, height: 24),
      ),
    );
  }
}
