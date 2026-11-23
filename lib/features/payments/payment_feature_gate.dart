import 'package:flutter/foundation.dart';

/// Enables the authenticated, persisted Payment Handling workflow in Debug.
/// Required database candidates must be reviewed and installed first.
const paymentHandlingEnabled =
    kDebugMode &&
    bool.fromEnvironment('JOBMATE_PAYMENT_HANDLING', defaultValue: false);

/// Optional isolated walkthrough. It is never the source for the real Payments
/// routes and remains separately gated for Debug-only presentations.
const paymentHandlingDemoEnabled =
    kDebugMode &&
    bool.fromEnvironment('JOBMATE_PAYMENT_HANDLING_DEMO', defaultValue: false);
