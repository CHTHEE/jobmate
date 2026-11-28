// Standalone, synthetic end-to-end Payment Handling walkthrough.
// Run with: flutter run -d chrome --target test/support/payment_handling_demo.dart
// This file is outside lib/ and is never imported by the production app.
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:jobmate/shared/theme/jobmate_theme.dart';

void main() {
  runApp(
    kDebugMode
        ? const PaymentHandlingDemoApp()
        : const _ReleaseUnavailableApp(),
  );
}

enum PaymentDemoRole { employer, jobSeeker }

@immutable
class DemoOfferSnapshot {
  const DemoOfferSnapshot({
    required this.id,
    required this.version,
    required this.minimumRateSen,
    required this.maximumRateSen,
  });

  final String id;
  final int version;
  final int minimumRateSen;
  final int maximumRateSen;
}

/// One process-local store is shared by both role views. It contains no client,
/// Supabase, Billplz, disk persistence, or production repository dependencies.
class PaymentHandlingDemoState extends ChangeNotifier {
  static final DateTime scheduledStart = DateTime.utc(2026, 11, 16, 9);
  static final DateTime scheduledEnd = DateTime.utc(2026, 11, 16, 13);
  static final DateTime effectiveCheckIn = DateTime.utc(2026, 11, 16, 9, 15);
  static final DateTime effectiveCheckOut = DateTime.utc(2026, 11, 16, 12, 45);

  final List<DemoOfferSnapshot> _offers = [];
  int _nextVersion = 1;
  String? _acceptedOfferId;
  int? _acceptedOfferVersion;
  int? _proposedFinalBaseSen;
  int? _confirmedFinalBaseSen;
  int _bonusSen = 0;
  bool _simulatedPaymentConfirmed = false;

  List<DemoOfferSnapshot> get offers => List.unmodifiable(_offers);
  DemoOfferSnapshot? get currentOffer => _offers.isEmpty ? null : _offers.last;
  DemoOfferSnapshot? get acceptedOffer {
    final offer = currentOffer;
    if (offer == null ||
        offer.id != _acceptedOfferId ||
        offer.version != _acceptedOfferVersion) {
      return null;
    }
    return offer;
  }

  bool get offerAccepted => acceptedOffer != null;
  int get workedMinutes => _effectiveOverlapMinutes();
  int? get minimumBaseSen => _salaryFor(currentOffer?.minimumRateSen);
  int? get maximumBaseSen => _salaryFor(currentOffer?.maximumRateSen);
  int? get proposedFinalBaseSen => _proposedFinalBaseSen;
  int? get confirmedFinalBaseSen => _confirmedFinalBaseSen;
  int get bonusSen => _bonusSen;
  int get totalSen => (_confirmedFinalBaseSen ?? 0) + _bonusSen;
  bool get simulatedPaymentConfirmed => _simulatedPaymentConfirmed;
  String get paymentStatus => _simulatedPaymentConfirmed
      ? 'Demo Payment — Simulated'
      : _confirmedFinalBaseSen == null
      ? 'Not ready — Job Seeker confirmation required'
      : 'Ready for Employer demo payment';

  void reset() {
    _offers.clear();
    _nextVersion = 1;
    _acceptedOfferId = null;
    _acceptedOfferVersion = null;
    _proposedFinalBaseSen = null;
    _confirmedFinalBaseSen = null;
    _bonusSen = 0;
    _simulatedPaymentConfirmed = false;
    notifyListeners();
  }

  DemoOfferSnapshot issueOffer({
    required int minimumRateSen,
    required int maximumRateSen,
  }) {
    if (minimumRateSen < 0 ||
        maximumRateSen < minimumRateSen ||
        maximumRateSen <= 0) {
      throw ArgumentError('Enter a valid hourly MYR salary range.');
    }
    final offer = DemoOfferSnapshot(
      id: 'demo-offer-$_nextVersion',
      version: _nextVersion++,
      minimumRateSen: minimumRateSen,
      maximumRateSen: maximumRateSen,
    );
    _offers.add(offer);
    // Issuing a new immutable version supersedes the previous workflow state.
    _acceptedOfferId = null;
    _acceptedOfferVersion = null;
    _proposedFinalBaseSen = null;
    _confirmedFinalBaseSen = null;
    _bonusSen = 0;
    _simulatedPaymentConfirmed = false;
    notifyListeners();
    return offer;
  }

  void acceptExactOffer({required String offerId, required int version}) {
    final current = currentOffer;
    if (current == null ||
        current.id != offerId ||
        current.version != version) {
      throw StateError('This Offer is stale. Review the current version.');
    }
    if (offerAccepted) return;
    _acceptedOfferId = offerId;
    _acceptedOfferVersion = version;
    notifyListeners();
  }

  void proposeFinalBase(int amountSen) {
    _requireAcceptedCurrentOffer();
    if (_confirmedFinalBaseSen != null || _simulatedPaymentConfirmed) {
      throw StateError('The confirmed Final Base Salary is locked.');
    }
    final minimum = minimumBaseSen!;
    final maximum = maximumBaseSen!;
    if (amountSen < minimum || amountSen > maximum) {
      throw StateError(
        'Final Base Salary must be within ${formatSen(minimum)}–${formatSen(maximum)}.',
      );
    }
    _proposedFinalBaseSen = amountSen;
    _confirmedFinalBaseSen = null;
    _bonusSen = 0;
    _simulatedPaymentConfirmed = false;
    notifyListeners();
  }

  void confirmExactFinalBase(int amountSen) {
    _requireAcceptedCurrentOffer();
    if (_proposedFinalBaseSen == null || amountSen != _proposedFinalBaseSen) {
      throw StateError('Confirm the exact Final Base Salary proposed.');
    }
    _confirmedFinalBaseSen = amountSen;
    notifyListeners();
  }

  void setBonus(int amountSen) {
    if (_confirmedFinalBaseSen == null || _simulatedPaymentConfirmed) {
      throw StateError(
        'Bonus is locked until salary confirmation and payment.',
      );
    }
    if (amountSen < 0) throw ArgumentError('Bonus cannot be negative.');
    _bonusSen = amountSen;
    notifyListeners();
  }

  void simulatePayment() {
    if (_confirmedFinalBaseSen == null || !offerAccepted) {
      throw StateError('Payment requires confirmed final salary.');
    }
    if (_simulatedPaymentConfirmed) return;
    _simulatedPaymentConfirmed = true;
    notifyListeners();
  }

  void _requireAcceptedCurrentOffer() {
    if (!offerAccepted) {
      throw StateError('The current exact Offer must be accepted first.');
    }
  }

  int _effectiveOverlapMinutes() {
    final start = effectiveCheckIn.isAfter(scheduledStart)
        ? effectiveCheckIn
        : scheduledStart;
    final end = effectiveCheckOut.isBefore(scheduledEnd)
        ? effectiveCheckOut
        : scheduledEnd;
    if (!end.isAfter(start)) return 0;
    return end.difference(start).inMinutes;
  }

  int? _salaryFor(int? hourlyRateSen) {
    if (hourlyRateSen == null || !offerAccepted) return null;
    // Round the aggregate to the nearest sen, with halves rounded upward.
    return (hourlyRateSen * workedMinutes + 30) ~/ 60;
  }
}

int parseDemoMoney(String input) {
  final value = input.trim();
  if (!RegExp(r'^(0|[1-9][0-9]{0,7})(\.\d{1,2})?$').hasMatch(value)) {
    throw const FormatException('Enter MYR with at most two decimal places.');
  }
  final parts = value.split('.');
  final result =
      int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  if (result > 999999999999) {
    throw const FormatException('Amount is too large.');
  }
  return result;
}

String formatSen(int amountSen) =>
    'MYR ${amountSen ~/ 100}.${(amountSen % 100).toString().padLeft(2, '0')}';

class PaymentHandlingDemoApp extends StatefulWidget {
  const PaymentHandlingDemoApp({super.key, this.store});
  final PaymentHandlingDemoState? store;

  @override
  State<PaymentHandlingDemoApp> createState() => _PaymentHandlingDemoAppState();
}

class _PaymentHandlingDemoAppState extends State<PaymentHandlingDemoApp> {
  late final PaymentHandlingDemoState _store =
      widget.store ?? PaymentHandlingDemoState();
  late final bool _ownsStore = widget.store == null;

  @override
  void dispose() {
    if (_ownsStore) _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JobMate Payment Handling Demo',
    debugShowCheckedModeBanner: false,
    theme: JobMateTheme.light(),
    home: _PaymentHandlingDemoPage(store: _store),
  );
}

class _PaymentHandlingDemoPage extends StatefulWidget {
  const _PaymentHandlingDemoPage({required this.store});
  final PaymentHandlingDemoState store;

  @override
  State<_PaymentHandlingDemoPage> createState() =>
      _PaymentHandlingDemoPageState();
}

class _PaymentHandlingDemoPageState extends State<_PaymentHandlingDemoPage> {
  final _minimumRate = TextEditingController(text: '20.00');
  final _maximumRate = TextEditingController(text: '25.00');
  final _finalBase = TextEditingController(text: '80.00');
  final _bonus = TextEditingController(text: '0.00');
  PaymentDemoRole _role = PaymentDemoRole.employer;
  String? _error;

  PaymentHandlingDemoState get store => widget.store;

  @override
  void dispose() {
    _minimumRate.dispose();
    _maximumRate.dispose();
    _finalBase.dispose();
    _bonus.dispose();
    super.dispose();
  }

  void _run(void Function() action) {
    setState(() => _error = null);
    try {
      action();
    } catch (error) {
      setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _confirmFinalBase() async {
    final proposed = store.proposedFinalBaseSen;
    if (proposed == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm exact Final Base Salary'),
        content: Text(
          'Confirm that the Employer-proposed amount is exactly ${formatSen(proposed)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Review amount'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm exact amount'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      _run(() => store.confirmExactFinalBase(proposed));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Payment Handling Demo'),
      automaticallyImplyLeading: false,
      actions: [
        IconButton(
          tooltip: 'Reset synthetic demo',
          onPressed: () {
            store.reset();
            setState(() {});
          },
          icon: const Icon(Icons.restart_alt),
        ),
      ],
    ),
    body: Column(
      children: [
        const _DemoBanner(),
        Expanded(
          child: AnimatedBuilder(
            animation: store,
            builder: (context, _) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'One shared synthetic Application',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Part-time · Hourly · Fictional JobMate application with one completed, Employer-verified Shift.',
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<PaymentDemoRole>(
                      segments: const [
                        ButtonSegment(
                          value: PaymentDemoRole.employer,
                          label: Text('Employer view'),
                          icon: Icon(Icons.business_outlined),
                        ),
                        ButtonSegment(
                          value: PaymentDemoRole.jobSeeker,
                          label: Text('Job Seeker view'),
                          icon: Icon(Icons.person_outline),
                        ),
                      ],
                      selected: {_role},
                      onSelectionChanged: (selection) => setState(() {
                        _role = selection.first;
                        _error = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    if (_error != null) ...[
                      _ErrorCard(message: _error!),
                      const SizedBox(height: 12),
                    ],
                    if (_role == PaymentDemoRole.employer)
                      _employerContent(context)
                    else
                      _jobSeekerContent(context),
                    const SizedBox(height: 12),
                    _paymentSummary(context),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _employerContent(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _DemoCard(
        title: '1. Salary Offer',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Create an immutable hourly Offer snapshot. A revised Offer creates a new version; previous versions remain unchanged.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('demo-minimum-rate'),
                    controller: _minimumRate,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Minimum MYR/hour',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('demo-maximum-rate'),
                    controller: _maximumRate,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Maximum MYR/hour',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('issue-demo-offer'),
              onPressed: () => _run(() {
                store.issueOffer(
                  minimumRateSen: parseDemoMoney(_minimumRate.text),
                  maximumRateSen: parseDemoMoney(_maximumRate.text),
                );
              }),
              child: Text(
                store.currentOffer == null
                    ? 'Issue salary Offer'
                    : 'Issue revised Offer version',
              ),
            ),
            if (store.currentOffer case final offer?) ...[
              const SizedBox(height: 10),
              Text(
                'Current Offer v${offer.version}: ${formatSen(offer.minimumRateSen)}–${formatSen(offer.maximumRateSen)} per hour',
                key: const Key('current-demo-offer'),
              ),
              Text(
                store.offerAccepted
                    ? 'Job Seeker accepted exact Offer v${offer.version}.'
                    : 'Waiting for the Job Seeker to accept exact Offer v${offer.version}.',
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      _workEvidenceCard(),
      const SizedBox(height: 12),
      _employerSalaryContent(),
    ],
  );

  Widget _jobSeekerContent(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _DemoCard(
        title: '1. Review and accept the exact Offer',
        child: store.currentOffer == null
            ? const Text('No salary Offer has been issued yet.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Application: JM-DEMO-APPLICATION-001',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'Offer ID: ${store.currentOffer!.id} · Version ${store.currentOffer!.version}',
                  ),
                  Text(
                    'Part-time · Hourly · ${formatSen(store.currentOffer!.minimumRateSen)}–${formatSen(store.currentOffer!.maximumRateSen)} per hour',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('accept-demo-offer'),
                    onPressed: store.offerAccepted
                        ? null
                        : () => _run(
                            () => store.acceptExactOffer(
                              offerId: store.currentOffer!.id,
                              version: store.currentOffer!.version,
                            ),
                          ),
                    child: Text(
                      store.offerAccepted
                          ? 'Exact Offer accepted'
                          : 'Accept Offer v${store.currentOffer!.version}',
                    ),
                  ),
                ],
              ),
      ),
      const SizedBox(height: 12),
      _workEvidenceCard(),
      const SizedBox(height: 12),
      _DemoCard(
        title: '3. Confirm Final Base Salary',
        child: store.proposedFinalBaseSen == null
            ? const Text('The Employer has not proposed a Final Base Salary.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Employer proposal: ${formatSen(store.proposedFinalBaseSen!)}',
                  ),
                  Text(
                    'Calculated range: ${formatSen(store.minimumBaseSen!)}–${formatSen(store.maximumBaseSen!)}',
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('confirm-demo-final-base'),
                    onPressed: store.confirmedFinalBaseSen != null
                        ? null
                        : _confirmFinalBase,
                    child: Text(
                      store.confirmedFinalBaseSen == null
                          ? 'Confirm exact ${formatSen(store.proposedFinalBaseSen!)}'
                          : 'Final Base Salary confirmed',
                    ),
                  ),
                ],
              ),
      ),
    ],
  );

  Widget _workEvidenceCard() => _DemoCard(
    title: '2. Completed work and payable quantity',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Scheduled Shift: 09:00–13:00 UTC · Completed and verified'),
        const Text('Effective Attendance: 09:15–12:45 UTC'),
        Text('Payable overlap: ${store.workedMinutes} minutes (3.5 hours)'),
        const SizedBox(height: 4),
        const Text(
          'Only scheduled/effective Attendance overlap is used. No break, overtime, or missing-attendance adjustment is inferred.',
        ),
        if (store.offerAccepted &&
            store.minimumBaseSen != null &&
            store.maximumBaseSen != null) ...[
          const SizedBox(height: 8),
          Text(
            'Calculated salary range: ${formatSen(store.minimumBaseSen!)}–${formatSen(store.maximumBaseSen!)}',
            key: const Key('demo-calculated-range'),
          ),
        ] else if (store.currentOffer != null)
          const Text('Accept the current exact Offer to calculate the range.'),
      ],
    ),
  );

  Widget _employerSalaryContent() => _DemoCard(
    title: '3. Employer proposes Final Base Salary',
    child: !store.offerAccepted
        ? const Text(
            'Available after the Job Seeker accepts the current Offer.',
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Allowed range: ${formatSen(store.minimumBaseSen!)}–${formatSen(store.maximumBaseSen!)}',
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('demo-final-base'),
                controller: _finalBase,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Final Base Salary (MYR)',
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                key: const Key('propose-demo-final-base'),
                onPressed: store.confirmedFinalBaseSen != null
                    ? null
                    : () => _run(
                        () => store.proposeFinalBase(
                          parseDemoMoney(_finalBase.text),
                        ),
                      ),
                child: const Text('Propose Final Base Salary'),
              ),
              if (store.proposedFinalBaseSen != null)
                Text(
                  store.confirmedFinalBaseSen == null
                      ? 'Waiting for Job Seeker confirmation of ${formatSen(store.proposedFinalBaseSen!)}.'
                      : 'Job Seeker confirmed ${formatSen(store.confirmedFinalBaseSen!)}.',
                ),
              if (store.confirmedFinalBaseSen != null) ...[
                const SizedBox(height: 10),
                TextField(
                  key: const Key('demo-bonus'),
                  controller: _bonus,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Optional voluntary bonus (MYR)',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('save-demo-bonus'),
                  onPressed: store.simulatedPaymentConfirmed
                      ? null
                      : () => _run(
                          () => store.setBonus(parseDemoMoney(_bonus.text)),
                        ),
                  child: const Text('Save optional bonus'),
                ),
                FilledButton.icon(
                  key: const Key('simulate-demo-payment'),
                  onPressed: store.simulatedPaymentConfirmed
                      ? null
                      : () => _run(store.simulatePayment),
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(
                    store.simulatedPaymentConfirmed
                        ? 'Demo Payment — Simulated'
                        : 'Proceed to simulated payment',
                  ),
                ),
              ],
            ],
          ),
  );

  Widget _paymentSummary(BuildContext context) => _DemoCard(
    title:
        'Payment Summary · ${_role == PaymentDemoRole.employer ? 'Employer' : 'Job Seeker'} view',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summaryRow('Job', 'Fictional Part-time Warehouse Assistant'),
        _summaryRow('Application / Engagement', 'JM-DEMO-APPLICATION-001'),
        _summaryRow(
          'Accepted salary terms',
          store.acceptedOffer == null
              ? 'No current Offer accepted'
              : 'Offer v${store.acceptedOffer!.version} · Hourly · ${formatSen(store.acceptedOffer!.minimumRateSen)}–${formatSen(store.acceptedOffer!.maximumRateSen)}',
        ),
        _summaryRow('Worked minutes', '${store.workedMinutes} minutes'),
        _summaryRow(
          'Calculated base range',
          store.minimumBaseSen == null
              ? 'Unavailable until the exact Offer is accepted'
              : '${formatSen(store.minimumBaseSen!)}–${formatSen(store.maximumBaseSen!)}',
        ),
        _summaryRow(
          'Final confirmed base',
          store.confirmedFinalBaseSen == null
              ? 'Not confirmed'
              : formatSen(store.confirmedFinalBaseSen!),
        ),
        _summaryRow('Optional bonus', formatSen(store.bonusSen)),
        _summaryRow(
          'Total amount',
          store.confirmedFinalBaseSen == null
              ? 'Unavailable until salary confirmation'
              : formatSen(store.totalSen),
        ),
        const Divider(),
        Text(
          store.paymentStatus,
          key: const Key('demo-payment-status'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (store.simulatedPaymentConfirmed)
          const Text(
            'Simulated Employer test-payment confirmation only. No Billplz request, wage transfer, or Job Seeker payout occurred.',
          ),
      ],
    ),
  );

  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: Text(label)),
        Expanded(flex: 3, child: Text(value)),
      ],
    ),
  );
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFF3CD),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.science_outlined, color: Color(0xFF594200)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'DEBUG DEMO ONLY · Synthetic records · Demo Payment — Simulated · No Supabase or Billplz calls',
                style: TextStyle(color: Color(0xFF594200), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DemoCard extends StatelessWidget {
  const _DemoCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(message, key: const Key('demo-error')),
    ),
  );
}

class _ReleaseUnavailableApp extends StatelessWidget {
  const _ReleaseUnavailableApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Text('This debug-only demo is unavailable in Release.'),
      ),
    ),
  );
}
