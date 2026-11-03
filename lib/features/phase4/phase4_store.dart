import 'package:flutter/foundation.dart';

import '../demo_work/local_attachment.dart';

const employerEvaluationCriteria = [
  'Communication',
  'Job Description Accuracy',
  'Professionalism',
  'Payment Reliability',
  'Work Environment',
  'Respect Towards Workers',
];
const workerEvaluationCriteria = [
  'Communication',
  'Responsibility',
  'Teamwork',
  'Professionalism',
  'Adaptability',
  'Punctuality',
];
List<String> evaluationCriteria(String role) =>
    role == 'employer' ? workerEvaluationCriteria : employerEvaluationCriteria;

class SampleAssignment {
  const SampleAssignment(
    this.id,
    this.job,
    this.worker,
    this.company,
    this.date, {
    this.completed = true,
  });
  final String id, job, worker, company;
  final DateTime date;
  final bool completed;
}

class SampleEvaluation {
  SampleEvaluation(
    this.assignmentId,
    this.author,
    this.ratings,
    this.feedback,
    this.date,
  );
  final String assignmentId, author, feedback;
  final Map<String, int> ratings;
  final DateTime date;
  double get average =>
      ratings.values.fold<int>(0, (a, b) => a + b) / ratings.length;
  String? reportId;
}

class EvaluationDraft {
  final Map<String, int> ratings = {};
  String feedback = '';
}

enum PaymentState {
  pending('Pending'),
  confirmed('Confirmed'),
  disputed('Disputed'),
  overdue('Overdue');

  const PaymentState(this.label);
  final String label;
}

class SamplePayment {
  SamplePayment(
    this.id,
    this.assignmentId,
    this.amount,
    this.date,
    this.method,
    this.reference, {
    this.state = PaymentState.pending,
    this.note = '',
    this.proof,
  });
  final String id, assignmentId, method, reference, note;
  final int amount;
  final DateTime date;
  PaymentState state;
  LocalAttachment? proof;
  String? disputeId;
}

class PaymentDraft {
  String worker = '';
  String assignmentId = '',
      amount = '',
      date = '',
      method = 'Bank transfer',
      reference = '',
      note = '';
  LocalAttachment? proof;
}

enum DisputeState {
  open('Open'),
  investigating('Investigating'),
  pendingInfo('Pending Info'),
  resolved('Resolved'),
  rejected('Rejected');

  const DisputeState(this.label);
  final String label;
  bool get terminal => this == resolved || this == rejected;
}

class SampleDispute {
  SampleDispute(
    this.id,
    this.category,
    this.subject,
    this.reason, {
    required DateTime date,
    this.linkId,
  }) : timeline = [(DisputeState.open, date)];
  final String id, category, subject, reason;
  final String? linkId;
  DisputeState state = DisputeState.open;
  String remarks = '', outcome = '';
  final List<(DisputeState, DateTime)> timeline;
  final List<String> requests = [];
}

class SampleAccount {
  SampleAccount(this.id, this.name, this.role, {this.state = 'Active'});
  final String id, name, role;
  String state;
}

class SampleModerationJob {
  SampleModerationJob(
    this.id,
    this.title,
    this.company, {
    this.state = 'Published',
  });
  final String id, title, company;
  String state, reason = '';
}

class ProfileDraft {
  String bio = '',
      location = '',
      availability = 'Available',
      skills = '',
      name = 'Demo candidate',
      industry = '',
      size = '',
      contact = '',
      website = '';
  final Set<String> categories = {};
  LocalAttachment? resume;
}

class Phase4Store extends ChangeNotifier {
  Phase4Store() {
    reset();
  }
  static final session = Phase4Store();
  int generation = 0;
  final List<SampleAssignment> assignments = [];
  final List<SampleEvaluation> evaluations = [];
  final Map<String, EvaluationDraft> evaluationDrafts = {};
  final List<SamplePayment> payments = [];
  final List<SampleDispute> disputes = [];
  final List<SampleAccount> accounts = [];
  final List<SampleModerationJob> jobs = [];
  final List<String> audit = [];
  final Map<String, String> formDrafts = {};
  final Map<String, ProfileDraft> profileDrafts = {};
  final Map<String, bool> notifications = {};
  PaymentDraft paymentDraft = PaymentDraft();
  SampleAssignment? assignment(String id) =>
      assignments.where((a) => a.id == id).firstOrNull;
  SamplePayment? payment(String id) =>
      payments.where((a) => a.id == id).firstOrNull;
  SampleDispute? dispute(String id) =>
      disputes.where((a) => a.id == id).firstOrNull;
  ProfileDraft profile(String role) => profileDrafts.putIfAbsent(
    role,
    () => ProfileDraft()
      ..name = role == 'employer' ? 'Demo Company' : 'Demo candidate',
  );
  EvaluationDraft evaluationDraft(String id, String role) =>
      evaluationDrafts.putIfAbsent('$id:$role', EvaluationDraft.new);
  SampleEvaluation? evaluation(String id, String role) => evaluations
      .where((e) => e.assignmentId == id && e.author == role)
      .firstOrNull;
  bool revealed(String id) =>
      evaluation(id, 'employer') != null &&
      evaluation(id, 'job_seeker') != null;
  void submitEvaluation(String id, String role) {
    final a = assignment(id),
        draft = evaluationDraft(id, role),
        criteria = evaluationCriteria(role);
    if (a == null ||
        !a.completed ||
        !['employer', 'job_seeker'].contains(role)) {
      throw StateError('Only completed demo assignments may be evaluated.');
    }
    if (evaluation(id, role) != null) {
      throw StateError('This demo evaluation has already been recorded.');
    }
    if (criteria.any(
          (c) =>
              !draft.ratings.containsKey(c) ||
              draft.ratings[c]! < 1 ||
              draft.ratings[c]! > 5,
        ) ||
        draft.ratings.length != 6) {
      throw StateError('Rate all six criteria from 1 to 5.');
    }
    if (draft.feedback.length > 300) {
      throw StateError('Feedback must be at most 300 characters.');
    }
    evaluations.add(
      SampleEvaluation(
        id,
        role,
        Map.unmodifiable(draft.ratings),
        draft.feedback.trim(),
        DateTime.now(),
      ),
    );
    evaluationDrafts.remove('$id:$role');
    notifyListeners();
  }

  void simulateCounterpart(String id, String role) {
    final other = role == 'employer' ? 'job_seeker' : 'employer';
    if (evaluation(id, role) == null || evaluation(id, other) != null) {
      throw StateError('Submit your demo evaluation first.');
    }
    evaluations.add(
      SampleEvaluation(
        id,
        other,
        {for (final c in evaluationCriteria(other)) c: 4},
        'Sample counterpart feedback, generated locally for preview.',
        DateTime.now(),
      ),
    );
    notifyListeners();
  }

  String addDispute(
    String category,
    String subject,
    String reason, {
    String? linkId,
  }) {
    if (reason.trim().isEmpty || reason.length > 1000) {
      throw StateError('Enter a reason of up to 1,000 characters.');
    }
    final id = 'demo-case-${disputes.length + 1}';
    disputes.add(
      SampleDispute(
        id,
        category,
        subject,
        reason.trim(),
        date: DateTime.now(),
        linkId: linkId,
      ),
    );
    notifyListeners();
    return id;
  }

  void reportEvaluation(String id, String viewer, String reason) {
    final other = viewer == 'employer' ? 'job_seeker' : 'employer',
        e = evaluation(id, viewer == 'employer' ? 'job_seeker' : 'employer');
    if (!revealed(id) || e == null || e.author != other || e.reportId != null) {
      throw StateError(
        'Only a revealed, received evaluation can be reported once.',
      );
    }
    e.reportId = addDispute(
      'Evaluation',
      assignment(id)!.job,
      reason,
      linkId: 'evaluation:$id:$other',
    );
    notifyListeners();
  }

  SamplePayment recordPayment() {
    final d = paymentDraft,
        a = assignment(d.assignmentId),
        value = double.tryParse(d.amount),
        date = DateTime.tryParse(d.date),
        today = DateTime.now();
    if (a == null || !a.completed) {
      throw StateError('Select a worker and a completed demo assignment.');
    }
    if (value == null ||
        !value.isFinite ||
        value <= 0 ||
        value > 10000000 ||
        !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(d.amount.trim())) {
      throw StateError(
        'Enter a positive amount with at most two decimal places.',
      );
    }
    if (date == null ||
        d.date != date.toIso8601String().substring(0, 10) ||
        date.isAfter(DateTime(today.year, today.month, today.day))) {
      throw StateError(
        'Enter a valid payment date, today or earlier, as YYYY-MM-DD.',
      );
    }
    if (!['Bank transfer', 'Cash', 'E-wallet', 'Other'].contains(d.method)) {
      throw StateError('Select a payment method.');
    }
    if (d.reference.length > 100 || d.note.length > 1000) {
      throw StateError(
        'Reference: maximum 100 characters; note: maximum 1,000.',
      );
    }
    if (payments.any(
      (p) =>
          p.assignmentId == d.assignmentId &&
          p.amount == (value * 100).round() &&
          p.date.year == date.year &&
          p.date.month == date.month &&
          p.date.day == date.day &&
          p.reference == d.reference.trim(),
    )) {
      throw StateError('This exact demo payment record already exists.');
    }
    final p = SamplePayment(
      'demo-payment-${payments.length + 1}',
      a.id,
      (value * 100).round(),
      date,
      d.method,
      d.reference.trim(),
      note: d.note.trim(),
      proof: d.proof,
    );
    payments.add(p);
    paymentDraft = PaymentDraft();
    notifyListeners();
    return p;
  }

  void confirmReceipt(String id) {
    final p = payment(id);
    if (p == null ||
        ![PaymentState.pending, PaymentState.overdue].contains(p.state)) {
      throw StateError(
        'Only pending or overdue demo records can be confirmed.',
      );
    }
    p.state = PaymentState.confirmed;
    notifyListeners();
  }

  void reportPayment(String id, String reason) {
    final p = payment(id);
    if (p == null ||
        ![PaymentState.pending, PaymentState.overdue].contains(p.state)) {
      throw StateError('This demo payment cannot be disputed.');
    }
    p.disputeId = addDispute(
      'Payment',
      assignment(p.assignmentId)!.job,
      reason,
      linkId: p.id,
    );
    p.state = PaymentState.disputed;
    notifyListeners();
  }

  void accountAction(String id, String next, String reason) {
    final a = accounts.where((a) => a.id == id).firstOrNull;
    if (a == null ||
        !['Active', 'Restricted', 'Suspended'].contains(next) ||
        a.state == next ||
        reason.trim().isEmpty) {
      throw StateError('Choose a new sample status and provide a reason.');
    }
    audit.add('DEMO: ${a.name}: ${a.state} → $next. ${reason.trim()}');
    a.state = next;
    notifyListeners();
  }

  void removeJob(String id, String reason) {
    final j = jobs.where((j) => j.id == id).firstOrNull;
    if (j == null || j.state == 'Removed' || reason.trim().isEmpty) {
      throw StateError('Provide a reason for an available sample job.');
    }
    j.state = 'Removed';
    j.reason = reason.trim();
    audit.add('DEMO: removed ${j.title}. ${j.reason}');
    notifyListeners();
  }

  void updateDispute(
    String id,
    DisputeState next,
    String text, {
    String party = 'Both parties',
  }) {
    final d = dispute(id);
    if (d == null ||
        d.state.terminal ||
        text.trim().isEmpty ||
        text.length > 1000) {
      throw StateError(
        'An open case and a reason/details of up to 1,000 characters are required.',
      );
    }
    if (next == DisputeState.open || next == d.state) {
      throw StateError('Choose a valid next state.');
    }
    if (next == DisputeState.pendingInfo) {
      d.requests.add('$party: ${text.trim()}');
    }
    if (next.terminal) d.outcome = text.trim();
    d.state = next;
    d.timeline.add((next, DateTime.now()));
    audit.add('DEMO: ${d.id} → ${next.label}: ${text.trim()}');
    notifyListeners();
  }

  void saveRemarks(String id, String value) {
    final d = dispute(id);
    if (d == null || value.length > 2000) {
      throw StateError('Remarks must be at most 2,000 characters.');
    }
    d.remarks = value;
    audit.add('DEMO: remarks saved for $id');
    notifyListeners();
  }

  void reset() {
    generation++;
    assignments.clear();
    evaluations.clear();
    evaluationDrafts.clear();
    payments.clear();
    disputes.clear();
    accounts.clear();
    jobs.clear();
    audit.clear();
    formDrafts.clear();
    profileDrafts.clear();
    notifications.clear();
    paymentDraft = PaymentDraft();
    final now = DateTime.now();
    for (var i = 1; i <= 4; i++) {
      assignments.add(
        SampleAssignment(
          'sample-assignment-$i',
          i.isEven ? 'Demo event support' : 'Demo retail shift',
          i == 3 ? 'Sample worker B' : 'Demo candidate (you)',
          i.isEven ? 'Demo Gather Events' : 'Demo Cedar Store',
          now.subtract(Duration(days: i + 3)),
          completed: i != 4,
        ),
      );
    }
    for (final role in ['job_seeker', 'employer']) {
      evaluations.add(
        SampleEvaluation(
          'sample-assignment-2',
          role,
          {
            for (final c in evaluationCriteria(role))
              c: role == 'employer' ? 4 : 5,
          },
          'Fictional feedback for the completed demo assignment.',
          now.subtract(const Duration(days: 2)),
        ),
      );
    }
    payments.addAll([
      SamplePayment(
        'demo-payment-1',
        'sample-assignment-1',
        18000,
        now.subtract(const Duration(days: 1)),
        'Bank transfer',
        'SAMPLE-001',
      ),
      SamplePayment(
        'demo-payment-2',
        'sample-assignment-2',
        25000,
        now.subtract(const Duration(days: 3)),
        'Cash',
        '',
        state: PaymentState.confirmed,
      ),
      SamplePayment(
        'demo-payment-3',
        'sample-assignment-3',
        12000,
        now.subtract(const Duration(days: 8)),
        'Other',
        'SAMPLE-003',
        state: PaymentState.overdue,
      ),
    ]);
    accounts.addAll([
      SampleAccount('sample-user-1', 'Sample candidate A', 'Job Seeker'),
      SampleAccount(
        'sample-user-2',
        'Sample employer A',
        'Employer',
        state: 'Restricted',
      ),
      SampleAccount(
        'sample-user-3',
        'Sample candidate B',
        'Job Seeker',
        state: 'Suspended',
      ),
    ]);
    jobs.addAll([
      SampleModerationJob(
        'sample-post-1',
        'Sample retail vacancy',
        'Demo Cedar Store',
      ),
      SampleModerationJob(
        'sample-post-2',
        'Sample event vacancy',
        'Demo Gather Events',
        state: 'Pending Review',
      ),
    ]);
    final d = SampleDispute(
      'demo-case-1',
      'Attendance',
      'Sample retail shift',
      'Sample evidence needs clarification.',
      date: now.subtract(const Duration(days: 2)),
    );
    disputes.add(d);
    notifyListeners();
  }
}

String sampleMoney(int cents) => 'RM ${(cents / 100).toStringAsFixed(2)}';
