import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/mobile_back_action.dart';
import '../../shared/widgets/responsive_layout.dart';
import 'payment_models.dart';
import 'payment_repository.dart';

const sandboxPaymentNotice =
    'Sandbox payments use test money. A confirmed employer test payment does not mean the worker received wages or a bank payout.';
String sandboxPaymentsRoot(String role) => switch (role) {
  'employer' => AppRoutes.employerPayments,
  'administrator' => AppRoutes.adminPayments,
  _ => AppRoutes.payments,
};

class SandboxPaymentsPage extends StatefulWidget {
  const SandboxPaymentsPage({
    super.key,
    this.role,
    this.assignmentId,
    this.paymentId,
    this.returnFromCheckout = false,
    this.repository,
    this.openCheckout,
  });
  final String? role, assignmentId, paymentId;
  final bool returnFromCheckout;
  final PaymentRepository? repository;
  final Future<bool> Function(Uri)? openCheckout;
  @override
  State<SandboxPaymentsPage> createState() => SandboxPaymentsPageState();
}

class SandboxPaymentsPageState extends State<SandboxPaymentsPage> {
  late final _repository =
      widget.repository ?? SupabasePaymentRepository(Supabase.instance.client);
  PaymentAccess? _access;
  List<PayableAssignment> _assignments = [];
  PayableAssignment? _detail;
  SandboxCheckout? _checkout;
  final _bonus = TextEditingController();
  bool _loading = true,
      _working = false,
      _opening = false,
      _confirming = false,
      _leaving = false;
  bool _integrationPending = false, _uncertain = false, _hasMore = false;
  int _offset = 0;
  String? _error, _requestId;
  SandboxCheckout? get _resumableCheckout {
    if (_role != 'employer' ||
        _detail == null ||
        !(_detail!.canPay || _detail!.canResumeCheckout)) {
      return null;
    }
    if (_checkout != null) return _checkout;
    for (final attempt in _detail?.attempts ?? <SandboxPaymentAttempt>[]) {
      if (attempt.status.unresolved && attempt.checkoutUrl != null) {
        return SandboxCheckout(
          paymentId: attempt.id,
          assignmentId: attempt.assignmentId,
          url: attempt.checkoutUrl!,
        );
      }
    }
    return null;
  }

  bool get _busy => _loading || _working || _opening || _confirming;
  bool get _dirty =>
      _checkout == null &&
      !_uncertain &&
      _bonus.text.trim().isNotEmpty &&
      !(_detail?.attempts.any(
            (a) => a.status == SandboxPaymentStatus.succeeded,
          ) ??
          false);
  bool get _detailRoute =>
      widget.assignmentId != null ||
      widget.paymentId != null ||
      widget.returnFromCheckout;
  String get _role => _access?.role ?? widget.role ?? 'job_seeker';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bonus.dispose();
    super.dispose();
  }

  Future<bool> confirmExit() async {
    if (_working || _opening || _confirming) return false;
    if (_leaving || !_dirty) return true;
    _confirming = true;
    final leave = await confirmDiscardChanges(context, true);
    _confirming = false;
    if (mounted && leave) setState(() => _leaving = true);
    return leave;
  }

  Future<void> _back() async {
    if (!await confirmExit() || !mounted) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) returnToPage(context, sandboxPaymentsRoot(_role));
    });
  }

  Future<void> _navigate(String destination) async {
    if (!await confirmExit() || !mounted) return;
    context.go(destination);
  }

  String _message(Object error) => error is StateError
      ? error.message.toString()
      : error is FormatException
      ? 'Payment data could not be verified. Refresh before continuing.'
      : 'Unable to load payment information. Check your connection and refresh.';

  Future<void> _load() async {
    if (_working || _opening) return;
    setState(() {
      _loading = true;
      _error = null;
      _integrationPending = false;
      _checkout = null;
    });
    try {
      final access = await _repository.access();
      if (widget.role != null && widget.role != access.role) {
        throw StateError('This payment page is unavailable for your account.');
      }
      if (!mounted) return;
      setState(() => _access = access);
      if (_detailRoute) {
        if (widget.assignmentId == null && widget.paymentId == null) {
          throw StateError(
            'No payment reference was supplied. Open Payments from the menu.',
          );
        }
        var detail = widget.assignmentId != null
            ? await _repository.assignment(widget.assignmentId!)
            : await _repository.forPayment(widget.paymentId!);
        if (widget.returnFromCheckout) {
          // A redirect (including ?success=true) never marks a payment paid.
          detail = await _repository.refresh(detail.id);
        }
        _repository.checkSession();
        if (mounted) setState(() => _detail = detail);
      } else {
        final rows = await _repository.assignments(offset: _offset, limit: 21);
        _repository.checkSession();
        if (mounted) {
          setState(() {
            _assignments = rows.take(20).toList();
            _hasMore = rows.length > 20;
          });
        }
      }
    } on PaymentIntegrationPending {
      if (mounted) {
        setState(() {
          _integrationPending = true;
          _detail = null;
          _assignments = [];
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _message(error);
          _detail = null;
          _assignments = [];
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pay() async {
    final detail = _detail;
    if (_busy ||
        _uncertain ||
        detail == null ||
        !detail.canPay ||
        _role != 'employer' ||
        _checkout != null) {
      return;
    }
    int bonus;
    try {
      bonus = parsePaymentBonus(_bonus.text);
      PaymentAmount(detail.amount.minorUnits + bonus, detail.amount.currency);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    setState(() => _confirming = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start sandbox payment?'),
        scrollable: true,
        content: Text(
          'Agreed amount: ${detail.amount.label}\nBonus: ${formatPaymentMinor(bonus)}\nTotal: ${formatPaymentMinor(detail.amount.minorUnits + bonus)}\n\n$sandboxPaymentNotice',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (mounted) setState(() => _confirming = false);
    if (!mounted || confirmed != true || _busy) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      _repository.checkSession();
      _requestId ??= const Uuid().v4();
      final checkout = await _repository.createCheckout(
        detail.id,
        _requestId!,
        bonusMinor: bonus,
      );
      _repository.checkSession();
      if (checkout.assignmentId != detail.id) {
        throw const FormatException('Mismatched checkout.');
      }
      if (mounted) setState(() => _checkout = checkout);
    } on PaymentIntegrationPending {
      if (mounted) setState(() => _integrationPending = true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _uncertain = true;
          _error = 'The checkout request could not be confirmed. Check payment status before starting another attempt.';
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _refreshStatus() async {
    if (_busy || _detail == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final detail = await _repository.refresh(_detail!.id);
      _repository.checkSession();
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _uncertain = false;
        if (detail.canPay ||
            detail.attempts.any(
              (a) => a.status == SandboxPaymentStatus.succeeded,
            )) {
          _requestId = null;
          _checkout = null;
        }
      });
    } on PaymentIntegrationPending {
      if (mounted) setState(() => _integrationPending = true);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openCheckout() async {
    final checkout = _resumableCheckout;
    if (_busy || checkout == null) return;
    setState(() => _opening = true);
    try {
      _repository.checkSession();
      // Separate preparation keeps launch attached to an explicit click on Web.
      final opened =
          await (widget.openCheckout?.call(checkout.url) ??
              launchUrl(
                checkout.url,
                mode: LaunchMode.externalApplication,
                webOnlyWindowName: '_blank',
              ));
      if (!opened) {
        throw StateError(
          'Checkout window was blocked. Allow popups and click Open sandbox checkout again.',
        );
      }
      _repository.checkSession();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Widget _notice() => WorkspaceCard(
    title: 'Sandbox mode',
    child: const Text(sandboxPaymentNotice),
  );
  Widget _state(String title, String message) => WorkspaceCard(
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh payments'),
        ),
      ],
    ),
  );

  Widget _assignmentCard(PayableAssignment assignment) => WorkspaceCard(
    title: assignment.jobTitle,
    subtitle: '${assignment.companyName} · ${assignment.workerName}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          assignment.amount.label,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(assignment.availability),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => context.push<void>(
                  '${sandboxPaymentsRoot(_role)}/assignments/${Uri.encodeComponent(assignment.id)}',
                ),
          child: const Text('View payment details'),
        ),
      ],
    ),
  );

  Widget _attempt(SandboxPaymentAttempt attempt) => Card.outlined(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                attempt.amount.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Chip(label: Text(attempt.status.label)),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText('Payment ID: ${attempt.id}'),
          if (attempt.providerReference != null)
            SelectableText('Provider reference: ${attempt.providerReference}'),
          if (attempt.method != null) Text('Method: ${attempt.method}'),
          Text('Created: ${_date(attempt.createdAt)}'),
          Text(
            'Agreed: ${formatPaymentMinor(attempt.agreedMinor)} · Bonus: ${formatPaymentMinor(attempt.bonusMinor)}',
          ),
          if (attempt.confirmedAt != null)
            Text('Provider confirmation: ${_date(attempt.confirmedAt!)}'),
          if (attempt.failureReason != null) Text(attempt.failureReason!),
          if (attempt.status == SandboxPaymentStatus.succeeded)
            const Text(
              'Employer test payment confirmed. No worker payout was made by JobMate.',
            ),
        ],
      ),
    ),
  );

  String _date(DateTime time) {
    final local = time.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  List<Widget> _details(PayableAssignment detail) => [
    WorkspaceCard(
      title: detail.jobTitle,
      subtitle: '${detail.companyName} · ${detail.workerName}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            detail.amount.label,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text(
                  detail.completed ? 'Work completed' : 'Work incomplete',
                ),
              ),
              Chip(
                label: Text(
                  detail.workVerified
                      ? 'Work verified'
                      : 'Verification required',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(detail.availability),
          if (_role == 'employer') ...[
            const SizedBox(height: 16),
            TextField(
              controller: _bonus,
              enabled:
                  !_busy && detail.canPay && !_uncertain && _checkout == null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Optional performance bonus (MYR)',
                hintText: '0.00',
                helperText: 'Adds to the agreed amount. The worker does not need to accept a bonus.',
                helperMaxLines: 3,
              ),
              onChanged: (_) => setState(() {
                _requestId = null;
                _error = null;
                _leaving = false;
              }),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  !_busy &&
                      detail.canPay &&
                      !_uncertain &&
                      _checkout == null &&
                      !_integrationPending
                  ? _pay
                  : null,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Pay now · Sandbox'),
            ),
          ],
          if (_role == 'employer' && _resumableCheckout != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _openCheckout,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open sandbox checkout'),
            ),
            const Text('After checkout, return here and check payment status.'),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _refreshStatus,
            icon: const Icon(Icons.refresh),
            label: const Text('Check payment status'),
          ),
          if (_role != 'employer')
            const Text(
              'Read-only payment history. The assignment employer initiates checkout.',
            ),
        ],
      ),
    ),
    const SizedBox(height: 20),
    Text('Payment attempts', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 12),
    if (detail.attempts.isEmpty)
      const Text('No payment attempts have been recorded for this assignment.'),
    for (final attempt in detail.attempts) _attempt(attempt),
  ];

  @override
  Widget build(BuildContext context) {
    final root = sandboxPaymentsRoot(_role);
    return PopScope(
      canPop: !_working && !_opening && (_leaving || !_dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _back();
      },
      child: AppWorkspace(
        title: _detailRoute ? 'Payment details' : 'Payments',
        path: root,
        role: _role,
        focused: _detailRoute,
        leading: !kIsWeb && _detailRoute
            ? BackButton(onPressed: _busy ? null : _back)
            : null,
        navigationLocked: _working || _opening || _confirming,
        onNavigate: _navigate,
        child: WorkspaceContent(
          maxWidth: 1120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_detailRoute)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy ? null : _back,
                    child: const Text('Payment history'),
                  ),
                ),
              PageHeading(
                title: _detailRoute ? 'Assignment payment' : 'Sandbox payments',
                description: _role == 'employer'
                    ? 'Pay for completed and verified assignments, then track provider-confirmed results.'
                    : 'Review employer sandbox payment attempts and their confirmed status.',
              ),
              _notice(),
              const SizedBox(height: 20),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_integrationPending)
                _state(
                  'Payments are being connected',
                  'Verified assignments and payment history will appear here after the assignment and payment services are connected. Checkout is currently unavailable.',
                )
              else if (_error != null && _detail == null)
                _state('Unable to open payments', _error!)
              else ...[
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_working || _opening) const LinearProgressIndicator(),
                if (_detail != null)
                  ..._details(_detail!)
                else if (_assignments.isEmpty)
                  _state(
                    'No payment assignments yet',
                    'Accepted assignments will appear here when the connected service makes them available.',
                  )
                else ...[
                  ResponsiveGrid(
                    minItemWidth: 330,
                    maxColumns: 2,
                    children: [
                      for (final assignment in _assignments)
                        _assignmentCard(assignment),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ResponsivePagination(
                    page: _offset ~/ 20 + 1,
                    onPrevious: _busy || _offset == 0
                        ? null
                        : () {
                            _offset -= 20;
                            _load();
                          },
                    onNext: _busy || !_hasMore
                        ? null
                        : () {
                            _offset += 20;
                            _load();
                          },
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
