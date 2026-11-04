import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_page.dart';
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
  Widget build(BuildContext context) => SandboxPaymentsPage(
    key: _page,
    role: widget.role,
    assignmentId: widget.assignmentId,
    paymentId: widget.paymentId,
    returnFromCheckout: widget.returnFromCheckout,
    repository: widget.repository,
    openCheckout: widget.openCheckout,
  );
}
