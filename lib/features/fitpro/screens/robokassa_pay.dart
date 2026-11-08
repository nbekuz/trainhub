import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:trainhub/components/toast/toast.dart';
import 'package:trainhub/core/theme/app_colors.dart';
import 'package:trainhub/features/fitpro/fit_api.dart';

enum RobokassaPayResult { paid, pending, failed, cancelled }

/// Opens Robokassa `payment_url`, then polls until PRO / payment is confirmed.
Future<RobokassaPayResult> openRobokassaPay(
  BuildContext context, {
  required String paymentUrl,
  required int paymentId,
  required String audience,
}) async {
  final result = await Navigator.of(context).push<RobokassaPayResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _RobokassaPayPage(
        paymentUrl: paymentUrl,
        paymentId: paymentId,
        audience: audience,
      ),
    ),
  );
  return result ?? RobokassaPayResult.cancelled;
}

class _RobokassaPayPage extends StatefulWidget {
  const _RobokassaPayPage({
    required this.paymentUrl,
    required this.paymentId,
    required this.audience,
  });

  final String paymentUrl;
  final int paymentId;
  final String audience;

  @override
  State<_RobokassaPayPage> createState() => _RobokassaPayPageState();
}

class _RobokassaPayPageState extends State<_RobokassaPayPage> {
  late final WebViewController _controller;
  late int _paymentId;
  var _phase = _PayPhase.webview;
  var _handled = false;

  @override
  void initState() {
    super.initState();
    _paymentId = widget.paymentId;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0D0D0D))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url;
            if (url.contains('/pay/success')) {
              _onPayReturned(success: true);
              return NavigationDecision.prevent;
            }
            if (url.contains('/pay/fail')) {
              _onPayReturned(success: false);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  Future<void> _onPayReturned({required bool success}) async {
    if (_handled || !mounted) return;
    _handled = true;
    if (!success) {
      setState(() => _phase = _PayPhase.failed);
      return;
    }
    setState(() => _phase = _PayPhase.polling);
    final ok = await _poll();
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, RobokassaPayResult.paid);
      return;
    }
    setState(() => _phase = _PayPhase.pendingTimeout);
  }

  Future<bool> _poll() async {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final payment = await FitApi.payment(_paymentId);
        if (payment['status']?.toString() == 'paid') return true;
      } catch (_) {}
      try {
        final sub = await FitApi.subscription(widget.audience);
        if (sub?['status']?.toString() == 'active') return true;
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  Future<void> _retry() async {
    try {
      final retry = await FitApi.retryPayment(_paymentId);
      final url = retry['payment_url']?.toString() ?? '';
      final nextId = int.tryParse('${retry['payment_id'] ?? retry['inv_id']}') ?? _paymentId;
      if (url.isEmpty) {
        Toast.error('Не удалось получить ссылку на оплату');
        return;
      }
      if (!mounted) return;
      _paymentId = nextId;
      setState(() {
        _phase = _PayPhase.webview;
        _handled = false;
      });
      await _controller.loadRequest(Uri.parse(url));
    } catch (error) {
      Toast.error(FitApi.messageOf(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fitBg,
      appBar: AppBar(
        backgroundColor: AppColors.fitBg,
        foregroundColor: Colors.white,
        title: const Text('Оплата PRO'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(
            context,
            _phase == _PayPhase.pendingTimeout ? RobokassaPayResult.pending : RobokassaPayResult.cancelled,
          ),
        ),
      ),
      body: switch (_phase) {
        _PayPhase.webview => WebViewWidget(controller: _controller),
        _PayPhase.polling => const _StatusPane(
            title: 'Подтверждаем оплату',
            subtitle: 'Платёж отправлен, ждём ответ банка…',
            loading: true,
          ),
        _PayPhase.failed => _StatusPane(
            title: 'Оплата не прошла',
            subtitle: 'Платёж отменён или карта отклонена. Можно попробовать снова.',
            actionLabel: 'Повторить',
            onAction: _retry,
          ),
        _PayPhase.pendingTimeout => _StatusPane(
            title: 'Оплата обрабатывается',
            subtitle: 'PRO появится через минуту. Обновите экран подписки.',
            actionLabel: 'Закрыть',
            onAction: () => Navigator.pop(context, RobokassaPayResult.pending),
          ),
      },
    );
  }
}

enum _PayPhase { webview, polling, failed, pendingTimeout }

class _StatusPane extends StatelessWidget {
  const _StatusPane({
    required this.title,
    required this.subtitle,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) ...[
              const CircularProgressIndicator(color: AppColors.accent),
              const SizedBox(height: 20),
            ],
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.fitGrey, fontSize: 14, height: 1.4)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
