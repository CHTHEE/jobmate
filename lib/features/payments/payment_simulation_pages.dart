import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'application_payment_repository.dart';
import 'payment_models.dart';
import 'payment_simulation_gateway.dart';

const paymentSimulationDuration = Duration(seconds: 30);

IconData _methodIcon(SimulationMethod method) => switch (method) {
  SimulationMethod.bank => Icons.account_balance_outlined,
  SimulationMethod.tng => Icons.account_balance_wallet_outlined,
};

class SimulationCheckout extends StatefulWidget {
  const SimulationCheckout({
    super.key,
    required this.gateway,
    required this.actor,
    required this.row,
    this.previous,
  });
  final PaymentSimulationGateway gateway;
  final String actor;
  final ApplicationPaymentSummary row;
  final SimulationAttempt? previous;

  @override
  State<SimulationCheckout> createState() => _SimulationCheckoutState();
}

class _SimulationCheckoutState extends State<SimulationCheckout> {
  late Future<List<SimulationRecipient>> _methods = _load();
  late SimulationMethod _method =
      widget.previous?.recipient.method ?? SimulationMethod.bank;
  late int? _bonus = widget.previous?.bonus ?? 0;

  Future<List<SimulationRecipient>> _load() => widget.gateway.recipients(
    widget.actor,
    applicationId: widget.row.applicationId,
  );

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<SimulationRecipient>>(
    future: _methods,
    builder: (context, snapshot) {
      final recipient = snapshot.data
          ?.where((r) => r.method == _method)
          .firstOrNull;
      final ready =
          snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError;
      return AlertDialog(
        title: const Text('Payment checkout'),
        scrollable: true,
        content: SizedBox(
          width: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.row.jobTitle),
              Text(widget.row.workerName),
              Text(
                'Confirmed salary: ${formatPaymentMinor(widget.row.confirmedBaseSen!)}',
              ),
              const SizedBox(height: 12),
              for (final method in SimulationMethod.values)
                Card.outlined(
                  child: ListTile(
                    leading: Icon(_methodIcon(method)),
                    title: Text(method.label),
                    selected: _method == method,
                    trailing: _method == method
                        ? const Icon(Icons.check_circle_outline)
                        : null,
                    onTap: () => setState(() => _method = method),
                  ),
                ),
              if (!ready && !snapshot.hasError)
                const LinearProgressIndicator(
                  semanticsLabel: 'Loading payment methods',
                )
              else if (snapshot.hasError) ...[
                const Text('Could not load recipient details.'),
                TextButton(
                  onPressed: () => setState(() => _methods = _load()),
                  child: const Text('Retry'),
                ),
              ] else if (recipient == null)
                const Text(
                  'The Worker has not saved details for this method. Choose another method or ask the Worker to add it.',
                )
              else
                Text(
                  [
                    recipient.name,
                    ?recipient.bank,
                    recipient.masked,
                  ].join(' · '),
                ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: widget.previous == null
                    ? null
                    : formatPaymentMinor(widget.previous!.bonus)
                          .replaceFirst('MYR ', ''),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Optional bonus (MYR)',
                  errorText: _bonus == null
                      ? 'Enter a valid MYR amount.'
                      : null,
                ),
                onChanged: (value) {
                  int? parsed;
                  try {
                    parsed = parsePaymentBonus(value);
                  } catch (_) {
                    /* Inline error. */
                  }
                  setState(() => _bonus = parsed);
                },
              ),
              const SizedBox(height: 12),
              Text(
                _bonus == null
                    ? 'Total unavailable'
                    : 'Total: ${formatPaymentMinor(widget.row.confirmedBaseSen! + _bonus!)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'JobMate records this payment for the project. No money will be transferred.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed:
                ready &&
                    recipient != null &&
                    _bonus != null &&
                    widget.gateway.actor == widget.actor
                ? () => Navigator.pop(
                    context,
                    SimulationAttempt(
                      actor: widget.actor,
                      settlement: widget.row,
                      recipient: recipient,
                      bonus: _bonus!,
                    ),
                  )
                : null,
            child: const Text('Pay now'),
          ),
        ],
      );
    },
  );
}

class SimulatedPaymentProcessingPage extends StatefulWidget {
  const SimulatedPaymentProcessingPage({
    super.key,
    required this.gateway,
    required this.attempt,
    required this.loadSettlements,
    this.duration = paymentSimulationDuration,
    this.resume = false,
    this.onDispatch,
    this.onResolved,
  });
  final PaymentSimulationGateway gateway;
  final SimulationAttempt attempt;
  final Future<List<ApplicationPaymentSummary>> Function() loadSettlements;
  final Duration duration;
  final bool resume;
  final VoidCallback? onDispatch;
  final VoidCallback? onResolved;

  @override
  State<SimulatedPaymentProcessingPage> createState() =>
      _SimulatedPaymentProcessingPageState();
}

class _SimulatedPaymentProcessingPageState
    extends State<SimulatedPaymentProcessingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final StreamSubscription<String?> _accounts;
  bool _invalidated = false;
  bool _recording = false;
  String? _error;
  bool _mayRetry = false;

  bool get _sameActor =>
      !_invalidated && widget.gateway.actor == widget.attempt.actor;

  @override
  void initState() {
    super.initState();
    _accounts = widget.gateway.accountChanges.listen((actor) {
      if (!mounted || actor == widget.attempt.actor) return;
      _progress.stop(canceled: true);
      setState(() => _invalidated = true);
    });
    if (widget.resume) {
      _progress.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_record(reconcile: true));
      });
    } else {
      unawaited(_simulate());
    }
  }

  Future<void> _simulate() async {
    try {
      await _progress.forward().orCancel;
    } on TickerCanceled {
      return;
    }
    if (mounted && _sameActor) await _record();
  }

  Future<void> _record({bool reconcile = false}) async {
    if (_recording || !_sameActor) return;
    setState(() {
      _recording = true;
      _error = null;
    });
    try {
      if (reconcile) {
        final rows = await widget.loadSettlements();
        if (!mounted || !_sameActor) return;
        final row = rows
            .where(
              (row) =>
                  row.applicationId == widget.attempt.settlement.applicationId,
            )
            .singleOrNull;
        if (row == null ||
            row.paymentId != null ||
            !row.canRecordDemoPayment ||
            row.proposalId != widget.attempt.settlement.proposalId ||
            row.confirmedBaseSen !=
                widget.attempt.settlement.confirmedBaseSen) {
          if (row?.paymentId != null) widget.onResolved?.call();
          setState(() {
            _mayRetry = false;
            _error = 'The settlement changed. Return to Settlement Details to see the latest payment state.';
          });
          return;
        }
      }
      widget.onDispatch?.call();
      final receipt = await widget.gateway.record(widget.attempt);
      if (!mounted || !_sameActor) return;
      widget.onResolved?.call();
      final row = widget.attempt.settlement;
      setState(() => _recording = false);
      unawaited(
        Navigator.of(context).pushReplacement<void, bool>(
          MaterialPageRoute(
            builder: (_) => SimulatedPaymentReceiptPage(
              gateway: widget.gateway,
              actor: widget.attempt.actor,
              row: row,
              receipt: receipt,
            ),
          ),
        ),
      );
    } catch (failure) {
      if (mounted && _sameActor) {
        final rejected =
            failure is PostgrestException &&
            const {
              '22023',
              '23505',
              '28000',
              '40001',
              '42501',
              '55000',
            }.contains(failure.code);
        if (rejected) widget.onResolved?.call();
        setState(() {
          _mayRetry = !rejected;
          _error = rejected
              ? 'The server declined this payment. Refresh the settlement and review the salary and recipient details.'
              : 'JobMate could not confirm that this payment was saved. Check the settlement before trying again.';
        });
      }
    } finally {
      if (mounted && _recording) setState(() => _recording = false);
    }
  }

  @override
  void dispose() {
    unawaited(_accounts.cancel());
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: !_recording || !_sameActor,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop && !_recording) _progress.stop(canceled: true);
    },
    child: _SimulationFrame(
      child: !_sameActor
          ? Column(
              children: [
                const Text(
                  'Session changed. Open Payment Handling for the current account.',
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            )
          : AnimatedBuilder(
              animation: _progress,
              builder: (context, _) {
                final fraction = _progress.value;
                final status = _recording || fraction >= 5 / 6
                    ? 'Finalising payment record'
                    : fraction < 1 / 6
                    ? 'Preparing payment'
                    : fraction < 1 / 2
                    ? 'Processing payment request'
                    : 'Confirming payment record';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      _methodIcon(widget.attempt.recipient.method),
                      size: 38,
                    ),
                    Text(
                      widget.attempt.recipient.method.label,
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      formatPaymentMinor(widget.attempt.total),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 20),
                    if (_error == null) ...[
                      const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: 18),
                      LinearProgressIndicator(value: fraction),
                      Text(
                        status,
                        textAlign: TextAlign.center,
                        semanticsLabel: status,
                      ),
                      if (fraction < 1)
                        Text(
                          'About ${(widget.duration.inMilliseconds * (1 - fraction) / 1000).ceil()} seconds remaining',
                          textAlign: TextAlign.center,
                        ),
                      const Text(
                        'Keep this page open while JobMate saves your payment.',
                        textAlign: TextAlign.center,
                      ),
                      if (!_recording && fraction < 1)
                        TextButton(
                          onPressed: () {
                            _progress.stop(canceled: true);
                            Navigator.pop(context, true);
                          },
                          child: const Text('Cancel and return to checkout'),
                        ),
                    ] else ...[
                      Text(_error!, textAlign: TextAlign.center),
                      if (_mayRetry)
                        FilledButton(
                          onPressed: () => _record(reconcile: true),
                          child: const Text('Check and retry'),
                        ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Return to Settlement Details'),
                      ),
                    ],
                  ],
                );
              },
            ),
    ),
  );
}

class SimulatedPaymentReceiptPage extends StatefulWidget {
  const SimulatedPaymentReceiptPage({
    super.key,
    required this.gateway,
    required this.actor,
    required this.row,
    required this.receipt,
    this.justRecorded = true,
    this.onBack,
  });
  final PaymentSimulationGateway gateway;
  final String actor;
  final ApplicationPaymentSummary row;
  final SimulationReceipt receipt;
  final bool justRecorded;
  final VoidCallback? onBack;

  @override
  State<SimulatedPaymentReceiptPage> createState() =>
      _SimulatedPaymentReceiptPageState();
}

class _SimulatedPaymentReceiptPageState
    extends State<SimulatedPaymentReceiptPage> {
  late final StreamSubscription<String?> _accounts;
  bool _invalidated = false;

  @override
  void initState() {
    super.initState();
    _accounts = widget.gateway.accountChanges.listen((actor) {
      if (mounted && actor != widget.actor) setState(() => _invalidated = true);
    });
  }

  @override
  void dispose() {
    unawaited(_accounts.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allowed = !_invalidated && widget.gateway.actor == widget.actor;
    final receipt = widget.receipt;
    final row = widget.row;
    final local = MaterialLocalizations.of(context);
    final time = receipt.recordedAt.toLocal();
    final date =
        '${local.formatMediumDate(time)} ${local.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
    return _SimulationFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (allowed) ...[
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.65, end: 1),
              duration: const Duration(milliseconds: 300),
              builder: (_, scale, icon) =>
                  Transform.scale(scale: scale, child: icon),
              child: Icon(
                Icons.check_circle_outline,
                size: 52,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Text(
              widget.justRecorded ? 'Payment recorded' : 'Payment receipt',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              formatPaymentMinor(receipt.total),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const Divider(height: 26),
            for (final item in <(String, String)>[
              ('Payment reference', receipt.reference),
              ('Job', row.jobTitle),
              ('Worker', row.workerName),
              ('Method', receipt.method?.label ?? 'No payment method recorded'),
              if (receipt.name != null) ('Recipient', receipt.name!),
              if (receipt.bank != null) ('Bank', receipt.bank!),
              if (receipt.masked != null)
                ('Recipient identifier', receipt.masked!),
              ('Confirmed salary', formatPaymentMinor(receipt.base)),
              ('Bonus', formatPaymentMinor(receipt.bonus)),
              ('Recorded', date),
              ('Status', 'Payment completed'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('${item.$1}: ${item.$2}'),
              ),
          ] else
            const Text('Session changed. Receipt details are hidden.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: widget.onBack ?? () => Navigator.pop(context),
            child: const Text('Back to Payment Handling'),
          ),
        ],
      ),
    );
  }
}

class _SimulationFrame extends StatelessWidget {
  const _SimulationFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('JobMate'),
      automaticallyImplyLeading: false,
    ),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    child,
                    const SizedBox(height: 12),
                    const Text(
                      'JobMate records payment completion for this project. No money is transferred.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
