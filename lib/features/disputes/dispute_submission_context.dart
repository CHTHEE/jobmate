class DisputeSubmissionContext {
  const DisputeSubmissionContext({
    required this.category,
    required this.relatedId,
    required this.jobTitle,
    this.companyName,
    this.workerName,
    this.recordLabel,
  }) : assert(category == 'recruitment' || category == 'work');

  final String category;
  final String relatedId;
  final String jobTitle;
  final String? companyName, workerName, recordLabel;
}
