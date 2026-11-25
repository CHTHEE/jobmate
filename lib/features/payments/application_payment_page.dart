import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/expandable_filter_bar.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../applications/module2_widgets.dart';
import 'application_payment_repository.dart';
import 'payment_models.dart';

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

class _ApplicationPaymentPageState extends State<ApplicationPaymentPage> {
  late final bool _ownsRepository = widget.repository == null;
  late final ApplicationPaymentRepository _repository =
      widget.repository ??
      ApplicationPaymentRepository(
        SupabaseApplicationPaymentSource(Supabase.instance.client),
      );
  bool _working = false;
  final _search = TextEditingController();
  String _statusFilter = '';

  bool get _isEmployer => widget.role == 'employer';

  @override
  void initState() {
    super.initState();
    _repository.load();
  }

  @override
  void dispose() {
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
        title: const Text('Demo Payment — Simulated'),
        content: Text(
          'Confirmed base: ${formatPaymentMinor(row.confirmedBaseSen!)}\n'
          'Voluntary bonus: ${formatPaymentMinor(bonus)}\n'
          'Total: ${formatPaymentMinor(row.confirmedBaseSen! + bonus)}\n\n'
          'Save this simulated payment record? No Billplz request, wage transfer or payout will occur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save simulated status'),
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
      'Simulated payment status saved. No money was transferred.',
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
          actions: [
            OutlinedButton.icon(
              onPressed: _working || _repository.loading
                  ? null
                  : _repository.load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh payments'),
            ),
          ],
        ),
        const _SimulationNotice(),
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
                'Simulated record saved',
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
                      child: Text('Simulated record saved'),
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
          actions: [
            OutlinedButton.icon(
              onPressed: _working || _repository.loading
                  ? null
                  : _repository.load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh settlement'),
            ),
          ],
        ),
        const _SimulationNotice(),
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
                    '${_hours(row.payableHours!)} hours',
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
      return ('recorded', 'Simulated payment recorded');
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
                    : '${_hours(row.payableHours!)} hours',
              ),
              const Text(
                'Payable hours use scheduled/effective Attendance overlap. The current Attendance contract has no approved unpaid-break records to deduct.',
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
                    'Salary confirmed. The Employer can add an optional bonus and save a simulated payment record.',
                  ),
              ],
              if (row.paymentId != null) ...[
                _row('Optional bonus', formatPaymentMinor(row.bonusSen)),
                _row('Total', formatPaymentMinor(row.totalSen!)),
                _row('Payment status', 'Demo Payment — Simulated'),
                if (row.recordedAt != null)
                  _row('Recorded at', _recordedTime(row.recordedAt!)),
                const Text('No Billplz request or wage transfer occurred.'),
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'The deployed settlement contract does not yet store a payment method or recipient account. This action records only a simulated payment status and optional bonus.',
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _working || _repository.loading
                          ? null
                          : () => _recordDemoPayment(row),
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Save Demo Payment — Simulated'),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: const Text('Additional technical details'),
                subtitle: const Text('Identifiers and proposal version'),
                children: [
                  _row('Application / Engagement', row.applicationId),
                  _row('Offer ID', row.offerId),
                  if (row.proposalId != null)
                    _row('Proposal ID', row.proposalId!),
                  if (row.proposalVersion != null)
                    _row('Salary proposal version', '${row.proposalVersion}'),
                  if (row.paymentId != null)
                    _row('Saved payment record', row.paymentId!),
                ],
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

  String _hours(double value) =>
      value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');

  String _recordedTime(String value) {
    final time = DateTime.parse(value).toLocal();
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(time)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(time))} (local time)';
  }
}

class _SimulationNotice extends StatelessWidget {
  const _SimulationNotice();

  @override
  Widget build(BuildContext context) => const Card(
    color: Color(0xFFFFF3CD),
    child: Padding(
      padding: EdgeInsets.all(14),
      child: Text(
        'FYP payment status is simulated. Saving a record does not contact Billplz, transfer wages or confirm a real payment.',
      ),
    ),
  );
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

  @override
  Widget build(BuildContext context) {
    final steps = <(String, bool)>[
      ('Offer accepted', true),
      (
        'Eligible work verified',
        row.blockingReason == null && row.payableHours != null,
      ),
      (
        'Engagement closed',
        row.calculatedMinSen != null && row.calculatedMaxSen != null,
      ),
      ('Final Salary proposed', row.proposalId != null),
      ('Worker confirmed', row.proposalStatus == 'confirmed'),
      ('Simulated payment recorded', row.paymentId != null),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final step in steps)
          Chip(
            avatar: Icon(
              step.$2 ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
            ),
            label: Text(step.$1),
          ),
      ],
    );
  }
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
