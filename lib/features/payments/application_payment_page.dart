import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/expandable_filter_bar.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../applications/module2_widgets.dart';
import 'application_payment_repository.dart';
import 'payment_feature_gate.dart';
import 'payment_models.dart';
import 'payment_simulation_gateway.dart';
import 'payment_simulation_pages.dart';

class ApplicationPaymentPage extends StatefulWidget {
  const ApplicationPaymentPage({
    super.key,
    required this.role,
    this.applicationId,
    this.repository,
  });

  final String role;
  final String? applicationId;
  final ApplicationPaymentRepository? repository;

  @override
  State<ApplicationPaymentPage> createState() => _ApplicationPaymentPageState();
}

class _ApplicationPaymentPageState extends State<ApplicationPaymentPage>
    with WidgetsBindingObserver {
  late final bool _ownsRepository = widget.repository == null;
  late final ApplicationPaymentRepository _repository =
      widget.repository ??
      ApplicationPaymentRepository(
        SupabaseApplicationPaymentSource(Supabase.instance.client),
      );
  bool _working = false;
  SimulationAttempt? _pendingSimulation;
  late final _simulation = SupabasePaymentSimulationGateway(
    Supabase.instance.client,
  );
  final _search = TextEditingController();
  String _statusFilter = '';
  Timer? _refreshTimer;

  bool get _isEmployer => widget.role == 'employer';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repository.load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted &&
          ModalRoute.isCurrentOf(context) != false &&
          !_working &&
          !_repository.loading) {
        unawaited(_repository.load(quietly: true));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_working) {
      unawaited(_repository.load(quietly: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _search.dispose();
    if (_ownsRepository) _repository.dispose();
    super.dispose();
  }

  Future<int?> _amount({
    required String title,
    required String label,
    required String initial,
    String? range,
    int? minimumSen,
    int? maximumSen,
  }) => _reviewDialog<int>(
    builder: (_) => _PaymentAmountDialog(
      title: title,
      label: label,
      initialValue: initial,
      range: range,
      minimumSen: minimumSen,
      maximumSen: maximumSen,
    ),
  );

  Future<T?> _reviewDialog<T>({required WidgetBuilder builder}) {
    final actor = _repository.source.userId;
    return showDialog<T>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: _repository,
        builder: (context, _) {
          if (actor == null || actor != _repository.source.userId) {
            return AlertDialog(
              title: const Text('Session changed'),
              content: const Text(
                'Close this dialog and refresh payments for your current account.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          }
          return builder(context);
        },
      ),
    );
  }

  Future<void> _propose(ApplicationPaymentSummary row) async {
    final actor = _repository.source.userId;
    final amount = await _amount(
      title: 'Propose Final Base Salary',
      label: 'Final Base Salary (MYR)',
      initial: formatPaymentMinor(row.calculatedMinSen!)
          .replaceFirst('MYR ', ''),
      range:
          '${formatPaymentMinor(row.calculatedMinSen!)}–${formatPaymentMinor(row.calculatedMaxSen!)}',
      minimumSen: row.calculatedMinSen,
      maximumSen: row.calculatedMaxSen,
    );
    if (amount == null || !mounted) return;
    await _act(
      () => _repository.mutate(
        () => _repository.source.propose(row, amount),
        expectedActor: actor,
      ),
      'Final Base Salary proposal saved.',
      actor,
    );
  }

  Future<void> _respond(
    ApplicationPaymentSummary row, {
    required bool accept,
  }) async {
    final actor = _repository.source.userId;
    final amount = row.proposedBaseSen!;
    final decision = await _reviewDialog<bool>(
      builder: (context) => AlertDialog(
        title: Text(
          accept ? 'Confirm exact Final Base Salary' : 'Reject salary proposal',
        ),
        content: Text(
          accept
              ? 'Confirm the exact Employer proposal of ${formatPaymentMinor(amount)}?'
              : 'Reject the Employer proposal of ${formatPaymentMinor(amount)}? The Employer may submit a new proposal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Review'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(accept ? 'Confirm exact amount' : 'Reject proposal'),
          ),
        ],
      ),
    );
    if (decision != true || !mounted) return;
    await _act(
      () => _repository.mutate(
        () => _repository.source.respond(row, accept: accept),
        expectedActor: actor,
      ),
      accept ? 'Final Base Salary confirmed.' : 'Salary proposal rejected.',
      actor,
    );
  }

  Future<void> _checkout(ApplicationPaymentSummary row) async {
    final actor = _repository.source.userId;
    if (_working || actor == null) return;
    setState(() => _working = true);
    SimulationAttempt? previous;
    try {
      while (mounted && _simulation.actor == actor) {
        final pending = _pendingSimulation;
        final resume =
            pending?.actor == actor &&
            pending?.settlement.applicationId == row.applicationId;
        final attempt = resume
            ? pending
            : await _reviewDialog<SimulationAttempt>(
                builder: (_) => SimulationCheckout(
                  gateway: _simulation,
                  actor: actor,
                  row: row,
                  previous: previous,
                ),
              );
        if (!mounted || attempt == null || _simulation.actor != actor) return;
        final returnToCheckout =
            await Navigator.of(context, rootNavigator: true).push<bool>(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => SimulatedPaymentProcessingPage(
                  gateway: _simulation,
                  attempt: attempt,
                  loadSettlements: _repository.source.list,
                  resume: resume,
                  onDispatch: () {
                    if (mounted) _pendingSimulation = attempt;
                  },
                  onResolved: () {
                    if (mounted) _pendingSimulation = null;
                  },
                ),
              ),
            );
        if (returnToCheckout != true) {
          if (mounted && _simulation.actor == actor) await _repository.load();
          return;
        }
        previous = attempt;
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _viewReceipt(ApplicationPaymentSummary row) async {
    final actor = _repository.source.userId;
    if (_working || actor == null) return;
    setState(() => _working = true);
    try {
      final receipt = await _simulation.receipt(actor, row);
      if (!mounted || _simulation.actor != actor || receipt == null) return;
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => SimulatedPaymentReceiptPage(
            gateway: _simulation,
            actor: actor,
            row: row,
            receipt: receipt,
            justRecorded: false,
          ),
        ),
      );
    } catch (_) {
      if (mounted && _simulation.actor == actor) {
        _show('Could not load the receipt. Refresh this settlement and retry.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _recordDemoPayment(ApplicationPaymentSummary row) async {
    final actor = _repository.source.userId;
    final bonus = await _amount(
      title: 'Optional voluntary bonus',
      label: 'Bonus (MYR)',
      initial: '0.00',
    );
    if (bonus == null || !mounted || actor != _repository.source.userId) return;
    final approved = await _reviewDialog<bool>(
      builder: (context) => AlertDialog(
        title: const Text('Record payment completion?'),
        content: Text(
          'Confirmed base: ${formatPaymentMinor(row.confirmedBaseSen!)}\n'
          'Voluntary bonus: ${formatPaymentMinor(bonus)}\n'
          'Total: ${formatPaymentMinor(row.confirmedBaseSen! + bonus)}\n\n'
          'Save this payment record? JobMate will store the status and receipt, but it will not transfer money.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Record payment'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await _act(
      () => _repository.mutate(
        () => _repository.source.recordDemoPayment(row, bonus),
        expectedActor: actor,
      ),
      'Payment status saved. No money was transferred.',
      actor,
    );
  }

  Future<void> _act(
    Future<void> Function() action,
    String success,
    String? actor,
  ) async {
    if (_working) return;
    if (actor == null || actor != _repository.source.userId) return;
    setState(() => _working = true);
    try {
      await action();
      if (mounted && actor == _repository.source.userId) _show(success);
    } catch (failure) {
      if (mounted && actor == _repository.source.userId) {
        _show(
          failure is PostgrestException && failure.code == '42501'
              ? 'This account is not authorized for that payment action.'
              : failure is StateError
              ? failure.message.toString()
              : 'Unable to update Payment Handling. Refresh and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => AppWorkspace(
    title: 'Payments',
    path: _isEmployer ? '/employer-payments' : '/payments',
    role: widget.role,
    child: WorkspaceContent(
      maxWidth: double.infinity,
      child: AnimatedBuilder(
        animation: _repository,
        builder: (context, _) => widget.applicationId == null
            ? _overview(context)
            : _details(context),
      ),
    ),
  );

  Widget _overview(BuildContext context) {
    final visible = _repository.summaries
        .where((row) {
          final search = _search.text.trim().toLowerCase();
          return (search.isEmpty ||
                  row.jobTitle.toLowerCase().contains(search) ||
                  row.workerName.toLowerCase().contains(search) ||
                  row.companyName.toLowerCase().contains(search)) &&
              (_statusFilter.isEmpty ||
                  _settlementState(row).$1 == _statusFilter);
        })
        .toList(growable: false);
    final counts = <String, int>{
      for (final key in [
        'ready',
        'awaiting',
        'confirmed',
        'blocked',
        'recorded',
      ])
        key: _repository.summaries
            .where((row) => _settlementState(row).$1 == key)
            .length,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading(
          title: 'Payment Overview',
          description: _isEmployer
              ? 'Review salary settlements for your hired workers.'
              : 'Review your accepted compensation and salary settlements.',
        ),
        if (_repository.loading || _working) const LinearProgressIndicator(),
        if (_repository.error != null) _errorState(),
        if (!_repository.loading && _repository.error == null) ...[
          ResponsiveGrid(
            minItemWidth: 170,
            maxColumns: 5,
            equalRowHeight: true,
            children: [
              _PaymentStat(
                'Ready for settlement',
                counts['ready']!,
                Icons.task_alt_outlined,
              ),
              _PaymentStat(
                'Awaiting confirmation',
                counts['awaiting']!,
                Icons.hourglass_top,
              ),
              _PaymentStat(
                'Confirmed salary',
                counts['confirmed']!,
                Icons.verified_outlined,
              ),
              _PaymentStat('Blocked', counts['blocked']!, Icons.block_outlined),
              _PaymentStat(
                'Payment completed',
                counts['recorded']!,
                Icons.receipt_long_outlined,
              ),
            ],
          ),
          if (_repository.summaries.isNotEmpty) ...[
            const SizedBox(height: 16),
            ExpandableFilterBar(
              search: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _isEmployer
                      ? 'Search job or worker'
                      : 'Search job or company',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
              activeCount: _statusFilter.isEmpty ? 0 : 1,
              onClear: () => setState(() => _statusFilter = ''),
              filters: [
                DropdownButtonFormField<String>(
                  key: ValueKey('settlement-status:$_statusFilter'),
                  initialValue: _statusFilter,
                  decoration: const InputDecoration(
                    labelText: 'Settlement status',
                  ),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All settlements')),
                    DropdownMenuItem(
                      value: 'ready',
                      child: Text('Ready for settlement'),
                    ),
                    DropdownMenuItem(
                      value: 'awaiting',
                      child: Text('Awaiting confirmation'),
                    ),
                    DropdownMenuItem(
                      value: 'confirmed',
                      child: Text('Confirmed salary'),
                    ),
                    DropdownMenuItem(value: 'blocked', child: Text('Blocked')),
                    DropdownMenuItem(
                      value: 'recorded',
                      child: Text('Payment completed'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _statusFilter = value ?? ''),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Showing ${visible.length} of ${_repository.summaries.length} settlements',
            ),
          ],
          const SizedBox(height: 16),
          if (_repository.summaries.isEmpty)
            const ModuleState(
              title: 'No settlements yet',
              message: 'No hired Payment-supported Applications with an accepted versioned Offer are available. Issue and accept the exact Offer in Applications, complete eligible work and close the Engagement first.',
            )
          else if (visible.isEmpty)
            const ModuleState(
              title: 'No matching settlements',
              message:
                  'Clear the search or status filter to see all settlements.',
            )
          else
            ResponsiveGrid(
              minItemWidth: 360,
              maxColumns: 3,
              equalRowHeight: true,
              children: [for (final row in visible) _overviewCard(row)],
            ),
        ],
      ],
    );
  }

  Widget _details(BuildContext context) {
    ApplicationPaymentSummary? row;
    for (final item in _repository.summaries) {
      if (item.applicationId == widget.applicationId) row = item;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(_paymentRoot),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back to Payment Overview'),
          ),
        ),
        PageHeading(
          title: row?.jobTitle ?? 'Settlement Details',
          description:
              'Review the engagement, salary progress and available actions.',
        ),
        if (_repository.loading || _working) const LinearProgressIndicator(),
        if (_repository.error != null)
          _errorState()
        else if (!_repository.loading && row == null)
          const ModuleState(
            title: 'Settlement unavailable',
            message: 'This settlement is unavailable for the current account or no longer exists.',
          )
        else if (row != null)
          _settlementDetails(row),
      ],
    );
  }

  String get _paymentRoot =>
      _isEmployer ? AppRoutes.employerPayments : AppRoutes.payments;

  Widget _errorState() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: ModuleState(
      title: 'Unable to load Payment Handling',
      message: _repository.error!,
      action: _repository.loading ? null : _repository.load,
      actionLabel: 'Retry',
    ),
  );

  Widget _overviewCard(ApplicationPaymentSummary row) {
    final state = _settlementState(row);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.jobTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(_isEmployer ? row.workerName : row.companyName),
                const SizedBox(height: 12),
                Chip(label: Text(state.$2)),
                if (row.payableHours != null)
                  _row(
                    'Verified payable work',
                    _payableTime(row.payableHours!),
                  ),
                if (row.calculatedMinSen != null &&
                    row.calculatedMaxSen != null)
                  _row(
                    'Eligible salary range',
                    '${formatPaymentMinor(row.calculatedMinSen!)}–${formatPaymentMinor(row.calculatedMaxSen!)}',
                  ),
                if (row.confirmedBaseSen != null)
                  _row(
                    'Confirmed base',
                    formatPaymentMinor(row.confirmedBaseSen!),
                  ),
                if (row.blockingReason case final reason?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      reason,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: FilledButton.icon(
                onPressed: () => context.push(
                  '$_paymentRoot/settlements/${row.applicationId}',
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('View Settlement'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (String, String) _settlementState(ApplicationPaymentSummary row) {
    if (row.paymentId != null) {
      return ('recorded', 'Payment completed');
    }
    if (row.blockingReason != null) return ('blocked', 'Settlement blocked');
    if (row.proposalStatus == 'pending') {
      return ('awaiting', 'Awaiting worker confirmation');
    }
    if (row.proposalStatus == 'confirmed') {
      return ('confirmed', 'Salary confirmed');
    }
    return (
      'ready',
      row.canPropose ? 'Ready for salary proposal' : 'Settlement in progress',
    );
  }

  Widget _settlementDetails(ApplicationPaymentSummary row) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Job and engagement',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              _row('Job', row.jobTitle),
              _row('Company', row.companyName),
              _row('Worker', row.workerName),
              _row('Employment type', 'Part-time'),
              const SizedBox(height: 12),
              _row(
                'Accepted Offer',
                'Version ${row.offerVersion} · Part-time · Hourly',
              ),
              const Divider(height: 32),
              Text(
                'Settlement progress',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              _PaymentProgress(row: row),
              const Divider(height: 32),
              Text(
                'Salary breakdown',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              _row(
                'Accepted hourly rate',
                row.salaryMinSen == null || row.salaryMaxSen == null
                    ? 'Incomplete hourly salary range'
                    : '${formatPaymentMinor(row.salaryMinSen!)}–${formatPaymentMinor(row.salaryMaxSen!)} / hour',
              ),
              _row(
                'Verified payable work',
                row.payableHours == null
                    ? 'Unavailable'
                    : _payableTime(row.payableHours!),
              ),
              _row(
                'Calculated salary range',
                row.calculatedMinSen == null || row.calculatedMaxSen == null
                    ? 'Unavailable'
                    : '${formatPaymentMinor(row.calculatedMinSen!)}–${formatPaymentMinor(row.calculatedMaxSen!)}',
              ),
              if (row.blockingReason case final reason?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Action unavailable: $reason',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (row.proposedBaseSen != null)
                _row(
                  'Employer Final Base proposal',
                  formatPaymentMinor(row.proposedBaseSen!),
                ),
              if (row.proposalStatus == 'pending')
                _row('Proposal status', 'Awaiting Job Seeker response'),
              if (row.proposalStatus == 'declined')
                _row(
                  'Proposal status',
                  'Rejected by Job Seeker; Employer may propose again',
                ),
              if (row.confirmedBaseSen != null)
                _row(
                  'Job Seeker confirmed base',
                  formatPaymentMinor(row.confirmedBaseSen!),
                ),
              if (row.paymentId == null && row.blockingReason == null) ...[
                if (row.proposalStatus == 'pending' && _isEmployer)
                  const Text(
                    'Waiting for the Job Seeker to confirm or reject this exact proposal.',
                  ),
                if (row.proposalStatus == null && !_isEmployer)
                  const Text(
                    'Waiting for the Employer to propose the Final Base Salary.',
                  ),
                if (row.proposalStatus == 'confirmed')
                  const Text(
                    'Salary confirmed. The Employer can add an optional bonus and complete the payment record.',
                  ),
              ],
              if (row.paymentId != null) ...[
                _row('Optional bonus', formatPaymentMinor(row.bonusSen)),
                _row('Total', formatPaymentMinor(row.totalSen!)),
                _row('Payment status', 'Completed'),
                if (row.recordedAt != null)
                  _row('Recorded at', _recordedTime(row.recordedAt!)),
              ],
              const Divider(height: 32),
              Text(
                'Current actions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isEmployer && row.canPropose)
                FilledButton(
                  onPressed: _working || _repository.loading
                      ? null
                      : () => _propose(row),
                  child: Text(
                    row.proposalStatus == 'declined'
                        ? 'Propose new Final Base Salary'
                        : 'Propose Final Base Salary',
                  ),
                ),
              if (!_isEmployer && row.canReject) ...[
                if (row.canConfirm)
                  FilledButton(
                    onPressed: _working || _repository.loading
                        ? null
                        : () => _respond(row, accept: true),
                    child: Text(
                      'Confirm exact ${formatPaymentMinor(row.proposedBaseSen!)}',
                    ),
                  ),
                TextButton(
                  onPressed: _working || _repository.loading
                      ? null
                      : () => _respond(row, accept: false),
                  child: const Text('Reject proposal'),
                ),
              ],
              if (_isEmployer && row.canRecordDemoPayment)
                if (paymentRecipientSimulationEnabled)
                  FilledButton.icon(
                    onPressed: _working || _repository.loading
                        ? null
                        : () => _checkout(row),
                    icon: const Icon(Icons.payment_outlined),
                    label: const Text('Continue to payment'),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Add an optional bonus, then record payment completion.',
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _working || _repository.loading
                            ? null
                            : () => _recordDemoPayment(row),
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('Record payment'),
                      ),
                    ],
                  ),
              if (paymentRecipientSimulationEnabled && row.paymentId != null)
                OutlinedButton.icon(
                  onPressed: _working || _repository.loading
                      ? null
                      : () => _viewReceipt(row),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('View receipt'),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 480
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(value),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: Text(label)),
                Expanded(flex: 3, child: Text(value)),
              ],
            ),
    ),
  );

  String _payableTime(double hours) {
    final minutes = (hours * 60).round();
    if (minutes < 60) return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
    final wholeHours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    final hourLabel = '$wholeHours ${wholeHours == 1 ? 'hour' : 'hours'}';
    return remainingMinutes == 0
        ? hourLabel
        : '$hourLabel $remainingMinutes minutes';
  }

  String _recordedTime(String value) {
    final time = DateTime.parse(value).toLocal();
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(time)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(time))} (local time)';
  }
}

class _PaymentStat extends StatelessWidget {
  const _PaymentStat(this.label, this.value, this.icon);
  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text('$value', style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    ),
  );
}

class _PaymentProgress extends StatelessWidget {
  const _PaymentProgress({required this.row});
  final ApplicationPaymentSummary row;

  static const _labels = [
    'Offer Accepted',
    'Work Verified',
    'Engagement Closed',
    'Salary Proposed',
    'Worker Confirmed',
    'Payment Completed',
  ];

  int get _currentIndex {
    if (row.paymentId != null) return _labels.length;
    if (row.proposalStatus == 'confirmed') return 5;
    if (row.proposalStatus == 'pending') return 4;
    if (row.proposalStatus == 'declined') return 3;
    if (row.proposalId != null) return 4;
    if (row.calculatedMinSen != null && row.calculatedMaxSen != null) return 3;
    if (row.payableHours != null) return 2;
    return 1;
  }

  _PaymentStepState _stateAt(int index) {
    if (_currentIndex >= _labels.length || index < _currentIndex) {
      return _PaymentStepState.completed;
    }
    return index == _currentIndex
        ? _PaymentStepState.current
        : _PaymentStepState.pending;
  }

  bool _connectorCompleted(int segment) => segment < _currentIndex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minimumStepWidth = 112.0;
        final horizontal =
            constraints.maxWidth >= _labels.length * minimumStepWidth;
        if (!horizontal) {
          return Column(
            children: [
              for (var index = 0; index < _labels.length; index++)
                _VerticalPaymentStep(
                  index: index,
                  label: _labels[index],
                  state: _stateAt(index),
                  connectorCompleted: _connectorCompleted(index),
                  showConnector: index < _labels.length - 1,
                ),
            ],
          );
        }
        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var index = 0; index < _labels.length; index++)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: index == 0
                              ? const SizedBox.shrink()
                              : _ProgressConnector(
                                  segment: index - 1,
                                  half: 'end',
                                  completed: _connectorCompleted(index - 1),
                                ),
                        ),
                        _PaymentStepMarker(
                          index: index,
                          label: _labels[index],
                          state: _stateAt(index),
                        ),
                        Expanded(
                          child: index == _labels.length - 1
                              ? const SizedBox.shrink()
                              : _ProgressConnector(
                                  segment: index,
                                  half: 'start',
                                  completed: _connectorCompleted(index),
                                ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final label in _labels)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(label, textAlign: TextAlign.center),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

enum _PaymentStepState { completed, current, pending }

class _PaymentStepMarker extends StatelessWidget {
  const _PaymentStepMarker({
    required this.index,
    required this.label,
    required this.state,
  });

  final int index;
  final String label;
  final _PaymentStepState state;

  @override
  Widget build(BuildContext context) {
    final completed = state == _PaymentStepState.completed;
    final current = state == _PaymentStepState.current;
    return Semantics(
      label: '$label: ${state.name}',
      child: Container(
        key: ValueKey('payment-step-$index-${state.name}'),
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: completed
              ? JobMateTheme.teal
              : current
              ? Colors.white
              : JobMateTheme.divider,
          border: current
              ? Border.all(color: JobMateTheme.teal, width: 2)
              : null,
        ),
        child: completed
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : Text(
                '${index + 1}',
                style: TextStyle(
                  color: current ? JobMateTheme.teal : JobMateTheme.body,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class _ProgressConnector extends StatelessWidget {
  const _ProgressConnector({
    required this.segment,
    required this.half,
    required this.completed,
  });

  final int segment;
  final String half;
  final bool completed;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('payment-connector-$segment-$half'),
    height: 3,
    color: completed ? JobMateTheme.teal : JobMateTheme.divider,
  );
}

class _VerticalPaymentStep extends StatelessWidget {
  const _VerticalPaymentStep({
    required this.index,
    required this.label,
    required this.state,
    required this.connectorCompleted,
    required this.showConnector,
  });

  final int index;
  final String label;
  final _PaymentStepState state;
  final bool connectorCompleted;
  final bool showConnector;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 32,
        child: Column(
          children: [
            _PaymentStepMarker(index: index, label: label, state: state),
            if (showConnector)
              Container(
                key: ValueKey('payment-vertical-connector-$index'),
                width: 3,
                height: 28,
                color: connectorCompleted
                    ? JobMateTheme.teal
                    : JobMateTheme.divider,
              ),
          ],
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          child: Text(label),
        ),
      ),
    ],
  );
}

class _PaymentAmountDialog extends StatefulWidget {
  const _PaymentAmountDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    this.range,
    this.minimumSen,
    this.maximumSen,
  });

  final String title;
  final String label;
  final String initialValue;
  final String? range;
  final int? minimumSen;
  final int? maximumSen;

  @override
  State<_PaymentAmountDialog> createState() => _PaymentAmountDialogState();
}

class _PaymentAmountDialogState extends State<_PaymentAmountDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  String? _error;

  void _submit() {
    try {
      final amount = parsePaymentMoney(_controller.text);
      if ((widget.minimumSen != null && amount < widget.minimumSen!) ||
          (widget.maximumSen != null && amount > widget.maximumSen!)) {
        throw const FormatException(
          'Enter an amount within the allowed salary range.',
        );
      }
      Navigator.pop(context, amount);
    } on FormatException catch (failure) {
      setState(() => _error = failure.message.toString());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.range != null) Text('Allowed range: ${widget.range}'),
          const SizedBox(height: 8),
          TextField(
            autofocus: true,
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: widget.label,
              errorText: _error,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Continue')),
    ],
  );
}
