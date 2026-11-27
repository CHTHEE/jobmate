import 'package:flutter/material.dart';

import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import 'payment_models.dart';

/// Process-local synthetic state used only by the opt-in Debug payment demo.
/// It deliberately has no Supabase, filesystem, Edge Function or Billplz client.
class PaymentHandlingDemoState extends ChangeNotifier {
  PaymentHandlingDemoState._();

  static final PaymentHandlingDemoState instance = PaymentHandlingDemoState._();

  static const applicationId = 'DEMO-APPLICATION-001';
  static const shiftMinutes = 240;
  static const effectiveAttendanceMinutes = 210;

  int _nextVersion = 1;
  String? _offerId;
  int? _offerVersion;
  int? _minimumRateSen;
  int? _maximumRateSen;
  String? _acceptedOfferId;
  int? _acceptedOfferVersion;
  int? _proposedBaseSen;
  int? _confirmedBaseSen;
  int _bonusSen = 0;
  bool _paymentRecorded = false;

  int get workedMinutes => effectiveAttendanceMinutes;
  int get payableMinutes => effectiveAttendanceMinutes;
  String? get offerId => _offerId;
  int? get offerVersion => _offerVersion;
  int? get minimumRateSen => _minimumRateSen;
  int? get maximumRateSen => _maximumRateSen;
  bool get hasOffer => _offerId != null;
  bool get offerAccepted =>
      hasOffer &&
      _acceptedOfferId == _offerId &&
      _acceptedOfferVersion == _offerVersion;
  int? get minimumBaseSen =>
      offerAccepted ? (_minimumRateSen! * payableMinutes + 30) ~/ 60 : null;
  int? get maximumBaseSen =>
      offerAccepted ? (_maximumRateSen! * payableMinutes + 30) ~/ 60 : null;
  int? get proposedBaseSen => _proposedBaseSen;
  int? get confirmedBaseSen => _confirmedBaseSen;
  int get bonusSen => _bonusSen;
  int get totalSen => (_confirmedBaseSen ?? 0) + _bonusSen;
  bool get paymentRecorded => _paymentRecorded;

  void issueOffer({required int minimumRateSen, required int maximumRateSen}) {
    if (minimumRateSen <= 0 || maximumRateSen < minimumRateSen) {
      throw ArgumentError('Enter a valid hourly MYR salary range.');
    }
    _offerId = 'DEMO-OFFER-$_nextVersion';
    _offerVersion = _nextVersion++;
    _minimumRateSen = minimumRateSen;
    _maximumRateSen = maximumRateSen;
    _acceptedOfferId = null;
    _acceptedOfferVersion = null;
    _proposedBaseSen = null;
    _confirmedBaseSen = null;
    _bonusSen = 0;
    _paymentRecorded = false;
    notifyListeners();
  }

  void acceptExactOffer({required String offerId, required int version}) {
    if (offerId != _offerId || version != _offerVersion) {
      throw StateError(
        'That Offer version is stale. Review the current Offer.',
      );
    }
    if (offerAccepted) return;
    _acceptedOfferId = offerId;
    _acceptedOfferVersion = version;
    notifyListeners();
  }

  void proposeFinalBase(int amountSen) {
    _requireAcceptedOffer();
    if (_paymentRecorded ||
        amountSen < minimumBaseSen! ||
        amountSen > maximumBaseSen!) {
      throw StateError(
        'Final Base Salary must be within ${formatPaymentMinor(minimumBaseSen!)}–${formatPaymentMinor(maximumBaseSen!)}.',
      );
    }
    _proposedBaseSen = amountSen;
    _confirmedBaseSen = null;
    _bonusSen = 0;
    notifyListeners();
  }

  void confirmExactFinalBase(int amountSen) {
    _requireAcceptedOffer();
    if (_proposedBaseSen == null ||
        _proposedBaseSen != amountSen ||
        _paymentRecorded) {
      throw StateError('Confirm the exact Employer proposal.');
    }
    _confirmedBaseSen = amountSen;
    notifyListeners();
  }

  void recordSimulatedPayment(int bonusSen) {
    if (_confirmedBaseSen == null || !offerAccepted || bonusSen < 0) {
      throw StateError(
        'Payment requires an accepted Offer and confirmed salary.',
      );
    }
    if (_paymentRecorded) return;
    _bonusSen = bonusSen;
    _paymentRecorded = true;
    notifyListeners();
  }

  void _requireAcceptedOffer() {
    if (!offerAccepted) {
      throw StateError('Accept the exact current Offer first.');
    }
  }

  /// Resets the process-local synthetic scenario; no durable data exists.
  @visibleForTesting
  void reset() {
    _nextVersion = 1;
    _offerId = null;
    _offerVersion = null;
    _minimumRateSen = null;
    _maximumRateSen = null;
    _acceptedOfferId = null;
    _acceptedOfferVersion = null;
    _proposedBaseSen = null;
    _confirmedBaseSen = null;
    _bonusSen = 0;
    _paymentRecorded = false;
    notifyListeners();
  }
}

class PaymentHandlingDemoPage extends StatefulWidget {
  const PaymentHandlingDemoPage({super.key, required this.initialRole});

  final String initialRole;

  @override
  State<PaymentHandlingDemoPage> createState() =>
      _PaymentHandlingDemoPageState();
}

class _PaymentHandlingDemoPageState extends State<PaymentHandlingDemoPage> {
  final _state = PaymentHandlingDemoState.instance;
  late String _role = widget.initialRole;

  bool get _isEmployer => _role == 'employer';

  Future<int?> _amount({
    required String title,
    required String label,
    String initial = '20.00',
  }) async {
    return showDialog<int>(
      context: context,
      builder: (_) => _PaymentAmountDialog(
        title: title,
        label: label,
        initialValue: initial,
      ),
    );
  }

  Future<void> _issueOffer() async {
    final minimum = await _amount(
      title: 'Issue salary Offer',
      label: 'Minimum hourly rate (MYR)',
    );
    if (minimum == null || !mounted) return;
    final maximum = await _amount(
      title: 'Issue salary Offer',
      label: 'Maximum hourly rate (MYR)',
      initial: '25.00',
    );
    if (maximum == null || !mounted) return;
    try {
      _state.issueOffer(minimumRateSen: minimum, maximumRateSen: maximum);
    } on ArgumentError catch (failure) {
      _message(failure.message.toString());
    }
  }

  Future<void> _propose() async {
    final amount = await _amount(
      title: 'Propose Final Base Salary',
      label: 'Final Base Salary (MYR)',
      initial: formatPaymentMinor(_state.minimumBaseSen!)
          .replaceFirst('MYR ', ''),
    );
    if (amount == null || !mounted) return;
    try {
      _state.proposeFinalBase(amount);
      _message('Synthetic salary proposal saved.');
    } on StateError catch (failure) {
      _message(failure.message.toString());
    }
  }

  Future<void> _confirm() async {
    final amount = _state.proposedBaseSen!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm exact Final Base Salary'),
        content: Text(
          'Confirm the exact Employer proposal of ${formatPaymentMinor(amount)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Review'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm exact amount'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _state.confirmExactFinalBase(amount);
  }

  Future<void> _recordPayment() async {
    final bonus = await _amount(
      title: 'Optional voluntary bonus',
      label: 'Bonus (MYR)',
      initial: '0.00',
    );
    if (bonus == null || !mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Demo Payment — Simulated'),
        content: Text(
          'Record ${formatPaymentMinor(_state.confirmedBaseSen! + bonus)}? This only updates synthetic in-memory demo state. No Supabase or Billplz request, wage transfer or payout will occur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Record simulated status'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) _state.recordSimulatedPayment(bonus);
  }

  void _message(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) => AppWorkspace(
    title: 'Payments',
    path: _isEmployer ? '/employer-payments' : '/payments',
    role: _role,
    child: WorkspaceContent(
      maxWidth: 1050,
      child: AnimatedBuilder(
        animation: _state,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeading(
              title: 'Payment Handling Demo',
              description: 'Synthetic Part-time hourly walkthrough. Switch demo roles below; all changes exist in memory only.',
            ),
            Card(
              color: const Color(0xFFFFF3CD),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'DEBUG DEMO ONLY · Synthetic Application, Offer, Shift and Attendance · Demo Payment — Simulated · No Supabase, Billplz or real wage transfer.',
                ),
              ),
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'employer', label: Text('Employer view')),
                ButtonSegment(
                  value: 'job_seeker',
                  label: Text('Job Seeker view'),
                ),
              ],
              selected: {_role},
              onSelectionChanged: (roles) =>
                  setState(() => _role = roles.first),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Part-time hourly · FYP Demo Barista',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text('Synthetic Employer · Synthetic Job Seeker'),
                    const SizedBox(height: 10),
                    _row(
                      'Synthetic completed Shift',
                      '09:00–13:00 · scheduled ${PaymentHandlingDemoState.shiftMinutes} minutes',
                    ),
                    _row(
                      'Effective Attendance overlap',
                      '09:15–12:45 · ${_state.workedMinutes} minutes',
                    ),
                    _row(
                      'Approved break deduction',
                      'None recorded in this demo; no break is inferred.',
                    ),
                    if (_state.hasOffer) ...[
                      _row(
                        _state.offerAccepted
                            ? 'Accepted salary terms'
                            : 'Offered salary terms',
                        'Offer v${_state.offerVersion} · ${formatPaymentMinor(_state.minimumRateSen!)}–${formatPaymentMinor(_state.maximumRateSen!)} / hour',
                      ),
                      _row(
                        'Exact Offer acceptance',
                        _state.offerAccepted
                            ? 'Accepted by Job Seeker'
                            : 'Awaiting exact version acceptance',
                      ),
                    ] else
                      _row('Offer', 'Not issued'),
                    if (_state.offerAccepted) ...[
                      _row(
                        'Calculated salary range',
                        '${formatPaymentMinor(_state.minimumBaseSen!)}–${formatPaymentMinor(_state.maximumBaseSen!)}',
                      ),
                      if (_state.proposedBaseSen != null)
                        _row(
                          'Employer Final Base proposal',
                          formatPaymentMinor(_state.proposedBaseSen!),
                        ),
                      if (_state.confirmedBaseSen != null)
                        _row(
                          'Job Seeker confirmed base',
                          formatPaymentMinor(_state.confirmedBaseSen!),
                        ),
                      if (_state.paymentRecorded) ...[
                        _row(
                          'Optional bonus',
                          formatPaymentMinor(_state.bonusSen),
                        ),
                        _row('Total', formatPaymentMinor(_state.totalSen)),
                        _row('Payment status', 'Demo Payment — Simulated'),
                        const Text('No payment request or transfer occurred.'),
                      ],
                    ],
                    const SizedBox(height: 14),
                    if (_isEmployer && !_state.hasOffer)
                      FilledButton(
                        onPressed: _issueOffer,
                        child: const Text('Issue salary Offer'),
                      ),
                    if (!_isEmployer &&
                        _state.hasOffer &&
                        !_state.offerAccepted)
                      FilledButton(
                        onPressed: () => _state.acceptExactOffer(
                          offerId: _state.offerId!,
                          version: _state.offerVersion!,
                        ),
                        child: Text(
                          'Accept exact Offer v${_state.offerVersion}',
                        ),
                      ),
                    if (_isEmployer &&
                        _state.offerAccepted &&
                        _state.confirmedBaseSen == null &&
                        !_state.paymentRecorded)
                      FilledButton(
                        onPressed: _propose,
                        child: const Text('Propose Final Base Salary'),
                      ),
                    if (!_isEmployer &&
                        _state.proposedBaseSen != null &&
                        _state.confirmedBaseSen == null)
                      FilledButton(
                        onPressed: _confirm,
                        child: Text(
                          'Confirm exact ${formatPaymentMinor(_state.proposedBaseSen!)}',
                        ),
                      ),
                    if (_isEmployer &&
                        _state.confirmedBaseSen != null &&
                        !_state.paymentRecorded)
                      FilledButton.icon(
                        onPressed: _recordPayment,
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text(
                          'Proceed to Demo Payment — Simulated',
                        ),
                      ),
                    if (_state.paymentRecorded)
                      OutlinedButton(
                        onPressed: _state.reset,
                        child: const Text('Reset synthetic demo'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: Text(label)),
        Expanded(flex: 3, child: Text(value)),
      ],
    ),
  );
}

class _PaymentAmountDialog extends StatefulWidget {
  const _PaymentAmountDialog({
    required this.title,
    required this.label,
    required this.initialValue,
  });

  final String title;
  final String label;
  final String initialValue;

  @override
  State<_PaymentAmountDialog> createState() => _PaymentAmountDialogState();
}

class _PaymentAmountDialogState extends State<_PaymentAmountDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      autofocus: true,
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: widget.label, errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          try {
            Navigator.pop(context, parsePaymentMoney(_controller.text));
          } on FormatException catch (failure) {
            setState(() => _error = failure.message.toString());
          }
        },
        child: const Text('Continue'),
      ),
    ],
  );
}
