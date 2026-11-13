import 'package:flutter/foundation.dart';

// A local invalidation only; authoritative unread values always come from RPCs.
final chatReadInvalidations = ValueNotifier<int>(0);
