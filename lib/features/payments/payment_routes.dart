import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_page.dart';
import 'application_payment_page.dart';
import 'payment_handling_demo_page.dart';
import 'payment_feature_gate.dart';
import 'payment_pages.dart';
import 'payment_repository.dart';

/// Each pushed payment page owns its guard/key, just like the existing job form.
GoRoute sandboxPaymentRoute(
  String path, {
  String? role,
  bool returnFromCheckout = false,
  PaymentRepository? repository,
  Future<bool> Function(Uri)? openCheckout,
}) {
  final guards = <LocalKey, Future<bool> Function()>{};
  return GoRoute(
    path: path,
    onExit: (_, state) async => await guards[state.pageKey]?.call() ?? true,
    pageBuilder: (_, state) => appPage(
      state,
      _PaymentRouteBody(
        key: ValueKey(state.pageKey),
        routeKey: state.pageKey,
        guards: guards,
        role: role,
        repository: repository,
        openCheckout: openCheckout,
        returnFromCheckout: returnFromCheckout,
        assignmentId: state.pathParameters['assignmentId'],
        paymentId: returnFromCheckout
            ? state.uri.queryParameters['payment_id']
            : state.pathParameters['paymentId'],
      ),
    ),
  );
}

class _PaymentRouteBody extends StatefulWidget {
  const _PaymentRouteBody({
    super.key,
    required this.routeKey,
    required this.guards,
    this.role,
    this.assignmentId,
    this.paymentId,
    required this.returnFromCheckout,
    this.repository,
    this.openCheckout,
  });
  final LocalKey routeKey;
  final Map<LocalKey, Future<bool> Function()> guards;
  final String? role, assignmentId, paymentId;
  final bool returnFromCheckout;
  final PaymentRepository? repository;
  final Future<bool> Function(Uri)? openCheckout;
  @override
  State<_PaymentRouteBody> createState() => _PaymentRouteBodyState();
}

class _PaymentRouteBodyState extends State<_PaymentRouteBody> {
  final _page = GlobalKey<SandboxPaymentsPageState>();
  Future<bool> _exit() async => await _page.currentState?.confirmExit() ?? true;
  @override
  void initState() {
    super.initState();
    widget.guards[widget.routeKey] = _exit;
  }

  @override
  void dispose() {
    if (widget.guards[widget.routeKey] == _exit) {
      widget.guards.remove(widget.routeKey);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eligibleRole =
        widget.role == 'employer' || widget.role == 'job_seeker';
    final rootPaymentPage =
        widget.assignmentId == null &&
        widget.paymentId == null &&
        !widget.returnFromCheckout;
    // The real, persisted settlement flow is application-based, not an
    // assignment checkout. Never silently open the legacy sandbox checkout
    // when real Payment Handling has been explicitly enabled.
    if (paymentHandlingEnabled && eligibleRole) {
      if (rootPaymentPage) {
        return ApplicationPaymentPage(role: widget.role!);
      }
      return _LegacyCheckoutDisabled(role: widget.role!);
    }
    if (paymentHandlingDemoEnabled && eligibleRole && rootPaymentPage) {
      return PaymentHandlingDemoPage(initialRole: widget.role!);
    }
    return SandboxPaymentsPage(
      key: _page,
      role: widget.role,
      assignmentId: widget.assignmentId,
      paymentId: widget.paymentId,
      returnFromCheckout: widget.returnFromCheckout,
      repository: widget.repository,
      openCheckout: widget.openCheckout,
    );
  }
}

/// A legacy deep link may still be present in older navigation or bookmarks.
/// In real Payment Handling mode, it must not invoke the old sandbox gateway.
class _LegacyCheckoutDisabled extends StatelessWidget {
  const _LegacyCheckoutDisabled({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Payment Handling')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 40),
              const SizedBox(height: 16),
              const Text(
                'This legacy sandbox checkout is not available in Payment Handling mode.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Use Payment Overview for verified salary proposals, worker confirmation and simulated payment records. No real payout is made.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go(sandboxPaymentsRoot(role)),
                child: const Text('Go to Payment Overview'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
