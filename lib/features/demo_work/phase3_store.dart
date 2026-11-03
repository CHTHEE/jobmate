import 'package:flutter/foundation.dart';

import 'local_attachment.dart';

class DemoAttendance {
  DemoAttendance({
    required this.id,
    required this.job,
    required this.worker,
    required this.start,
    required this.end,
    this.checkIn,
    this.checkOut,
    this.review = 'Pending',
    this.description = '',
    this.mine = true,
    this.locationReady = false,
  });
  final String id, job, worker;
  final DateTime start, end;
  final bool mine;
  DateTime? checkIn, checkOut;
  String review, description, flagReason = '';
  bool locationReady;
  final List<LocalAttachment> evidence = [];
  String get state => checkOut != null
      ? 'Checked Out'
      : checkIn != null
      ? 'Checked In'
      : 'Not Started';
  Duration elapsed(DateTime now) =>
      checkIn == null ? Duration.zero : (checkOut ?? now).difference(checkIn!);
}

class EvidenceDraft {
  String description = '';
  final List<LocalAttachment> files = [];
}

class DemoMessage {
  DemoMessage(
    this.sender,
    this.text,
    this.time, {
    this.attachments = const [],
    this.receipt = 'Sent',
  });
  final String sender, text;
  final DateTime time;
  final List<LocalAttachment> attachments;
  String receipt;
}

class DemoConversation {
  DemoConversation(this.id, this.job, this.company, this.worker);
  final String id, job, company, worker;
  final List<DemoMessage> messages = [];
  final Map<String, int> unread = {'job_seeker': 1, 'employer': 0};
  final Map<String, String> drafts = {};
  final Map<String, List<LocalAttachment>> attachmentDrafts = {};
}

class Phase3Store extends ChangeNotifier {
  Phase3Store() {
    reset();
  }
  static final session = Phase3Store();
  final List<DemoAttendance> attendance = [];
  final Map<String, EvidenceDraft> evidenceDrafts = {};
  final List<DemoConversation> conversations = [];
  final Map<String, String> flagDrafts = {};
  int generation = 0;
  String locationAddress = '', locationDraft = '';
  double markerX = .5, markerY = .5;
  bool locationConfirmed = false;
  DemoAttendance? record(String id) =>
      attendance.where((r) => r.id == id).firstOrNull;
  DemoConversation? conversation(String id) =>
      conversations.where((r) => r.id == id).firstOrNull;
  EvidenceDraft evidenceDraft(String id) =>
      evidenceDrafts.putIfAbsent(id, EvidenceDraft.new);
  void simulateLocation(String id) {
    final r = record(id);
    if (r == null) return;
    r.locationReady = true;
    notifyListeners();
  }

  void clock(String id, {required bool checkingIn, DateTime? now}) {
    final r = record(id);
    if (r == null || !r.mine) throw StateError('Demo assignment unavailable.');
    if (checkingIn) {
      if (!r.locationReady || r.checkIn != null) {
        throw StateError('Simulate location first; check-in is allowed once.');
      }
      r.checkIn = now ?? DateTime.now();
    } else {
      if (r.checkIn == null || r.checkOut != null) {
        throw StateError('Check in before checking out.');
      }
      final time = now ?? DateTime.now();
      if (time.isBefore(r.checkIn!)) {
        throw StateError('Check-out cannot precede check-in.');
      }
      r.checkOut = time;
    }
    notifyListeners();
  }

  void submitEvidence(String id) {
    final r = record(id), draft = evidenceDraft(id);
    if (r == null || !r.mine || r.checkOut == null) {
      throw StateError('Check out before submitting evidence.');
    }
    if (r.evidence.isNotEmpty) {
      throw StateError('Demo evidence has already been submitted.');
    }
    if (draft.description.trim().isEmpty ||
        draft.description.length > 2000 ||
        draft.files.isEmpty ||
        draft.files.length > 5) {
      throw StateError(
        'Add 1–5 files and a description of up to 2,000 characters.',
      );
    }
    r.description = draft.description.trim();
    r.evidence.addAll(draft.files);
    evidenceDrafts.remove(id);
    notifyListeners();
  }

  void review(String id, {required bool verify, String reason = ''}) {
    final r = record(id);
    if (r == null || r.review != 'Pending' || r.checkOut == null) {
      throw StateError('Only completed, pending demo records can be reviewed.');
    }
    if (verify && r.evidence.isEmpty) {
      throw StateError('Evidence is required before verifying work.');
    }
    if (!verify && (reason.trim().isEmpty || reason.length > 1000)) {
      throw StateError('Enter a flag reason of up to 1,000 characters.');
    }
    r.review = verify ? 'Verified' : 'Flagged';
    r.flagReason = verify ? '' : reason.trim();
    notifyListeners();
  }

  void send(String id, String role) {
    final c = conversation(id);
    if (c == null || !['job_seeker', 'employer'].contains(role)) {
      throw StateError('Demo conversation unavailable.');
    }
    final text = (c.drafts[role] ?? '').trim(),
        files = c.attachmentDrafts[role] ?? [];
    if ((text.isEmpty && files.isEmpty) ||
        text.length > 2000 ||
        files.length > 5) {
      throw StateError('Enter a message or attach up to five files.');
    }
    c.messages.add(
      DemoMessage(
        role,
        text,
        DateTime.now(),
        attachments: List.unmodifiable(files),
      ),
    );
    c.drafts.remove(role);
    c.attachmentDrafts.remove(role);
    final other = role == 'job_seeker' ? 'employer' : 'job_seeker';
    c.unread[other] = (c.unread[other] ?? 0) + 1;
    notifyListeners();
  }

  void read(String id, String role) {
    final c = conversation(id);
    if (c == null) return;
    c.unread[role] = 0;
    for (final m in c.messages) {
      if (m.sender != role) m.receipt = 'Read';
    }
    notifyListeners();
  }

  void simulateReceipts(String id, String role) {
    final c = conversation(id);
    if (c == null) return;
    for (final m in c.messages.where((m) => m.sender == role)) {
      m.receipt = m.receipt == 'Sent' ? 'Delivered' : 'Read';
    }
    notifyListeners();
  }

  void moveMarker(double x, double y) {
    markerX = x.clamp(.05, .95);
    markerY = y.clamp(.05, .95);
    locationConfirmed = false;
    notifyListeners();
  }

  void confirmLocation(String address) {
    if (address.trim().isEmpty || address.length > 300) {
      throw StateError('Enter a demo address of up to 300 characters.');
    }
    locationAddress = address.trim();
    locationDraft = locationAddress;
    locationConfirmed = true;
    notifyListeners();
  }

  void reset() {
    generation++;
    attendance.clear();
    evidenceDrafts.clear();
    conversations.clear();
    flagDrafts.clear();
    locationAddress = '';
    locationDraft = '';
    markerX = .5;
    markerY = .5;
    locationConfirmed = false;
    final now = DateTime.now(),
        today = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
          9,
        );
    attendance.add(
      DemoAttendance(
        id: 'today',
        job: 'Demo retail shift',
        worker: 'Demo candidate (you)',
        start: today,
        end: today.add(const Duration(hours: 8)),
      ),
    );
    for (var i = 1; i <= 3; i++) {
      final start = today.subtract(Duration(days: i));
      final r = DemoAttendance(
        id: 'shift-$i',
        job: i == 2 ? 'Demo event setup' : 'Demo retail shift',
        worker: i == 3 ? 'Sample worker B' : 'Demo candidate (you)',
        start: start,
        end: start.add(const Duration(hours: 8)),
        checkIn: start.add(const Duration(minutes: 5)),
        checkOut: start.add(const Duration(hours: 8)),
        review: i == 1
            ? 'Pending'
            : i == 2
            ? 'Flagged'
            : 'Verified',
        description:
            'Fictional shift summary. Tasks completed and work area prepared.',
        mine: i < 3,
        locationReady: true,
      );
      r.evidence.add(
        LocalAttachment('sample-evidence.pdf', Uint8List(0), 'application/pdf'),
      );
      if (i == 2) {
        r.flagReason = 'Sample review: completion details need clarification.';
      }
      attendance.add(r);
    }
    for (var i = 1; i <= 3; i++) {
      final c = DemoConversation(
        'chat-$i',
        i == 2 ? 'Demo event setup' : 'Demo retail shift',
        'Demo Cedar Store',
        'Demo candidate (you)',
      );
      if (i != 3) {
        c.messages.add(
          DemoMessage(
            'employer',
            'Welcome to the fictional shift. Please review the schedule.',
            now.subtract(const Duration(hours: 2)),
            receipt: 'Read',
          ),
        );
        c.messages.add(
          DemoMessage(
            'job_seeker',
            'Thank you. I will check the demo schedule.',
            now.subtract(const Duration(hours: 1)),
            receipt: 'Delivered',
          ),
        );
      }
      if (i == 3) c.unread['job_seeker'] = 0;
      conversations.add(c);
    }
    notifyListeners();
  }
}
