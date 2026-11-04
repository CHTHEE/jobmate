// Separate developer-only entry point. lib/main.dart never imports this preview.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:jobmate/features/payments/payment_models.dart';
import 'package:jobmate/features/payments/payment_routes.dart';
import 'package:jobmate/shared/navigation/app_routes.dart';
import 'package:jobmate/shared/navigation/app_page.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';

import 'payment_preview_repository.dart';

void main() => runApp(const PaymentPreviewApp());

class PaymentPreviewApp extends StatefulWidget {
  const PaymentPreviewApp({super.key});
  @override
  State<PaymentPreviewApp> createState() => _PaymentPreviewAppState();
}

class _PaymentPreviewAppState extends State<PaymentPreviewApp> {
  @override
  void initState() {
    super.initState();
    configureAppNavigation();
  }

  final _data = PaymentPreviewData();
  final _navigator = GlobalKey<NavigatorState>();
  late final GoRouter _router = GoRouter(
    navigatorKey: _navigator,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => _PreviewCases(data: _data),
      ),
      for (final (root, role) in [
        (AppRoutes.employerPayments, 'employer'),
        (AppRoutes.payments, 'job_seeker'),
        (AppRoutes.adminPayments, 'administrator'),
      ]) ...[
        sandboxPaymentRoute(
          root,
          role: role,
          repository: PreviewPaymentRepository(_data, role),
          openCheckout: _checkout,
        ),
        sandboxPaymentRoute(
          '$root/assignments/:assignmentId',
          role: role,
          repository: PreviewPaymentRepository(_data, role),
          openCheckout: _checkout,
        ),
        sandboxPaymentRoute(
          '$root/:paymentId',
          role: role,
          repository: PreviewPaymentRepository(_data, role),
          openCheckout: _checkout,
        ),
      ],
    ],
    errorBuilder: (context, _) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This preview includes Payments only.'),
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('Preview cases'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<bool> _checkout(Uri uri) async {
    if (uri.host != 'www.billplz-sandbox.com' ||
        uri.path != '/bills/ui-preview-only') {
      throw StateError('This preview never opens external checkout URLs.');
    }
    final choice = await showDialog<SandboxPaymentStatus>(
      context: _navigator.currentContext!,
      builder: (context) => AlertDialog(
        title: const Text('Simulated checkout · UI preview only'),
        scrollable: true,
        content: const Text(
          'No Billplz request is made. Choose a fictional outcome, then click Check payment status on the Payment page. A failed bank transaction can leave a Bill due.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, SandboxPaymentStatus.pending),
            child: const Text('Simulate due · Pending'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, SandboxPaymentStatus.cancelled),
            child: const Text('Simulate deleted · Cancelled'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, SandboxPaymentStatus.succeeded),
            child: const Text('Simulate paid · Confirmed'),
          ),
        ],
      ),
    );
    if (choice != null) _data.simulateResult(choice);
    return true; // Closing a preview window does not imply cancellation/payment.
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'JobMate Payment UI Preview',
    debugShowCheckedModeBanner: false,
    theme: JobMateTheme.light(),
    routerConfig: _router,
    builder: (context, child) => Column(
      children: [
        Material(
          color: const Color(0xFFFFF3CD),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'UI PREVIEW · FICTIONAL DATA\nNo Billplz calls or saved payments.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF594200)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _router.go('/'),
                    child: const Text('Preview cases'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child!),
      ],
    ),
  );
}

class _PreviewCases extends StatefulWidget {
  const _PreviewCases({required this.data});
  final PaymentPreviewData data;
  @override
  State<_PreviewCases> createState() => _PreviewCasesState();
}

class _PreviewCasesState extends State<_PreviewCases> {
  late PaymentPreviewScenario _scenario = widget.data.scenario;
  Future<void> _open(String root, {bool details = false}) async {
    await context.push(
      details ? '$root/assignments/$previewAssignmentId' : root,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Payment preview cases'),
      automaticallyImplyLeading: false,
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Test the UI before integration',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Select a fictional scenario, then open a role view. Role views share local attempts until you select or reset a scenario. No sign-in or credentials are needed. This does not test real payment, RLS, notifications or gateway callbacks.',
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<PaymentPreviewScenario>(
                initialValue: _scenario,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Preview scenario',
                ),
                items: [
                  for (final scenario in PaymentPreviewScenario.values)
                    DropdownMenuItem(
                      value: scenario,
                      child: Text(
                        scenario.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _scenario = value;
                      widget.data.reset(value);
                    });
                  }
                },
              ),
              TextButton(
                onPressed: () => setState(() => widget.data.reset(_scenario)),
                child: const Text('Reset selected scenario'),
              ),
              Text('Local preview attempts: ${widget.data.attempts.length}'),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () =>
                    _open(AppRoutes.employerPayments, details: true),
                child: const Text('Open Employer payment'),
              ),
              OutlinedButton(
                onPressed: () => _open(AppRoutes.payments),
                child: const Text('Open Job Seeker history'),
              ),
              OutlinedButton(
                onPressed: () => _open(AppRoutes.adminPayments),
                child: const Text('Open Admin history'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Quick walkthrough: Ready → enter Bonus → Pay now → Continue → Open sandbox checkout → choose a simulated outcome → Check payment status. Use Payment history to inspect the local attempt.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
