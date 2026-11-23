import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import 'application_payment_repository.dart';
import 'payment_models.dart';

class ApplicationPaymentPage extends StatefulWidget {
  const ApplicationPaymentPage({
    super.key,
    required this.role,
    this.repository,
  });

  final String role;
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

  bool get _isEmployer => widget.role == 'employer';

  @override
  void initState() {
    super.initState();
    _repository.load();
  }

  @override
  void dispose() {
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
      maxWidth: 1050,
      child: AnimatedBuilder(
        animation: _repository,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeading(
              title: 'Payment Handling',
              description: _isEmployer
                  ? 'Review closed Engagements, propose an eligible Final Base Salary and save a clearly labelled simulated payment status.'
                  : 'Review accepted compensation, respond to the Employer’s exact salary proposal and see saved payment status.',
            ),
            const Card(
              color: Color(0xFFFFF3CD),
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'FYP payment status is simulated. Saving a record does not contact Billplz, transfer wages or confirm a real payment.',
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _working || _repository.loading
                    ? null
                    : _repository.load,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh payments'),
              ),
            ),
            if (_repository.loading || _working)
              const LinearProgressIndicator(),
            if (_repository.error != null) ...[
              const SizedBox(height: 12),
              Text(
                _repository.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              OutlinedButton.icon(
                onPressed: _repository.loading ? null : _repository.load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
            if (!_repository.loading &&
                _repository.error == null &&
                _repository.summaries.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'No hired Payment-supported Applications with an accepted versioned Offer are available. Issue and accept the exact Offer in Applications, complete eligible work and close the Engagement first.',
                  ),
                ),
              ),
            for (final row in _repository.summaries) _summaryCard(row),
          ],
        ),
      ),
    ),
  );

  Widget _summaryCard(ApplicationPaymentSummary row) => Card(
    margin: const EdgeInsets.symmetric(vertical: 8),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(row.jobTitle, style: Theme.of(context).textTheme.titleLarge),
          Text('${row.companyName} · ${row.workerName}'),
          const SizedBox(height: 12),
          _row('Application / Engagement', row.applicationId),
          _row(
            'Accepted Offer',
            'Version ${row.offerVersion} · Part-time · Hourly',
          ),
          _row('Offer ID', row.offerId),
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
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          if (row.proposalVersion != null)
            _row('Salary proposal version', '${row.proposalVersion}'),
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
            _row('Saved payment record', row.paymentId!),
            if (row.recordedAt != null)
              _row('Recorded at', _recordedTime(row.recordedAt!)),
            const Text('No Billplz request or wage transfer occurred.'),
          ],
          const SizedBox(height: 12),
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
            FilledButton.icon(
              onPressed: _working || _repository.loading
                  ? null
                  : () => _recordDemoPayment(row),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Save Demo Payment — Simulated'),
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
