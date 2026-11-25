import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_page.dart';
import '../../shared/navigation/app_routes.dart';
import '../applications/module2_widgets.dart';
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
        applicationId: state.pathParameters['applicationId'],
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
    this.applicationId,
    this.paymentId,
    required this.returnFromCheckout,
    this.repository,
    this.openCheckout,
  });
  final LocalKey routeKey;
  final Map<LocalKey, Future<bool> Function()> guards;
  final String? role, assignmentId, applicationId, paymentId;
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
        widget.applicationId == null &&
        widget.paymentId == null &&
        !widget.returnFromCheckout;
    // The injected repository keeps the offline Sandbox preview independent
    // from the normal application routes.
    if (widget.repository == null) {
      if (eligibleRole && (rootPaymentPage || widget.applicationId != null)) {
        final role = widget.role!;
        if (paymentHandlingEnabled) {
          final auth = Supabase.instance.client.auth;
          return StreamBuilder<AuthState>(
            stream: auth.onAuthStateChange,
            builder: (_, _) => Module2Gate(
              key: ValueKey(auth.currentUser?.id),
              role: role,
              child: ApplicationPaymentPage(
                role: role,
                applicationId: widget.applicationId,
              ),
            ),
          );
        }
        if (paymentHandlingDemoEnabled) {
          return PaymentHandlingDemoPage(initialRole: role);
        }
      }
      if (eligibleRole || widget.returnFromCheckout) {
        return _PaymentUnavailable(role: eligibleRole ? widget.role : null);
      }
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

/// Old checkout links and disabled features do not start a Sandbox checkout.
class _PaymentUnavailable extends StatelessWidget {
  const _PaymentUnavailable({required this.role});

  final String? role;

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
              Text(
                role != null && paymentHandlingEnabled
                    ? 'This legacy sandbox checkout is unavailable. Open Payment Overview to manage salary proposals and simulated payment records.'
                    : 'Payment Handling is unavailable here.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go(
                  role != null && paymentHandlingEnabled
                      ? sandboxPaymentsRoot(role!)
                      : AppRoutes.home,
                ),
                child: Text(
                  role != null && paymentHandlingEnabled
                      ? 'Go to Payment Overview'
                      : 'Go to Home',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
