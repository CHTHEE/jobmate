import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../jobs/job_display.dart';
import 'module2_repository.dart';
import 'module2_widgets.dart';

class JobFacts extends StatelessWidget {
  const JobFacts(this.job, {super.key});
  final BrowseJob job;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 8,
    children: [
      for (final key in ['location', 'employment_type', 'work_arrangement'])
        Chip(label: Text(jobLabel(job.text(key)))),
      Text('Vacancies: ${job.text('vacancies')}'),
      Text('Deadline: ${jobDate(job.fields['application_deadline'])}'),
      if (job.fields['salary_visible'] == true)
        Text('Salary: ${jobSalary(job.fields)}')
      else
        const Text('Salary not disclosed'),
    ],
  );
}

class JobDetailsPage extends StatelessWidget {
  const JobDetailsPage({super.key, required this.jobId, this.repository});
  final String jobId;
  final Module2Repository? repository;
  @override
  Widget build(BuildContext context) {
    final repo = repository ?? Module2Repository.session;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final job = repo.job(jobId);
        return AppWorkspace(
          title: 'Job Details',
          leading: kIsWeb
              ? null
              : BackButton(
                  onPressed: () => moduleBack(context, AppRoutes.browseJobs),
                ),
          path: AppRoutes.browseJobs,
          role: 'job_seeker',
          child: WorkspaceContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => moduleBack(context, AppRoutes.browseJobs),
                    icon: kIsWeb ? null : const Icon(Icons.arrow_back),
                    label: const Text('Back to Browse Jobs'),
                  ),
                ),
                const DemoNotice(),
                if (job == null)
                  const ModuleState(
                    title: 'Job unavailable',
                    message: 'This demo job does not exist. Refresh resets the demo environment.',
                  )
                else ...[
                  PageHeading(title: job.title, description: job.company),
                  WorkspaceCard(
                    leading: const Icon(Icons.business_outlined),
                    title: job.title,
                    subtitle: job.company,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Fictional company • verification not connected',
                        ),
                        const SizedBox(height: 16),
                        JobFacts(job),
                        const SizedBox(height: 16),
                        if (job.unavailable() case final String reason)
                          Text(reason),
                        if (repo.applied(job.id))
                          const Text(
                            'Already applied in this demo session. View My Applications for the current status.',
                          ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton(
                            onPressed:
                                job.unavailable() != null ||
                                    repo.applied(job.id)
                                ? null
                                : () => moduleModal<void>(
                                    context,
                                    ApplyDemoForm(job: job, repository: repo),
                                  ),
                            child: const Text('Apply Now (demo)'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () => repo.toggleSave(job.id),
                            icon: Icon(
                              repo.saved(job.id)
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                            ),
                            label: Text(
                              repo.saved(job.id)
                                  ? 'Unsave Job (demo)'
                                  : 'Save Job (demo)',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  WorkspaceCard(
                    title: 'Role Overview',
                    child: Text(
                      job.text('role_overview').isEmpty
                          ? 'Not provided'
                          : job.text('role_overview'),
                    ),
                  ),
                  for (final key in [
                    'responsibilities',
                    'requirements',
                    'benefits',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: WorkspaceCard(
                        title: jobLabel(key),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (job.bullets(key).isEmpty)
                              const Text('Not provided'),
                            for (final bullet in job.bullets(key))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('• $bullet'),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class ApplyDemoForm extends StatefulWidget {
  const ApplyDemoForm({super.key, required this.job, required this.repository});
  final BrowseJob job;
  final Module2Repository repository;
  @override
  State<ApplyDemoForm> createState() => _ApplyDemoFormState();
}

class _ApplyDemoFormState extends State<ApplyDemoForm> {
  late final draftKey = 'cover:${widget.job.id}';
  late final note = TextEditingController(
    text: widget.repository.noteDraft(draftKey),
  );
  bool busy = false, success = false, leaving = false;
  String? error;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> close() async {
    if (busy) return;
    if (!success && note.text.trim().isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard cover note?'),
          content: const Text('This demo note has not been saved.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() => leaving = true);
    widget.repository.clearNoteDraft(draftKey);
    // Rebuild PopScope before asking Navigator to close the modal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> submit() async {
    if (busy || success) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.submit(widget.job.id, note.text);
      widget.repository.clearNoteDraft(draftKey);
      if (mounted) setState(() => success = true);
    } on StateError catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not update the demo. Your note is preserved; retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving || (!busy && (success || note.text.trim().isEmpty)),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) close();
    },
    child: ModalBody(
      title: success
          ? 'Demo application recorded'
          : 'Apply to ${widget.job.title}',
      actions: [
        TextButton(
          onPressed: busy ? null : close,
          child: Text(success ? 'Done' : 'Cancel'),
        ),
        if (!success)
          FilledButton(
            onPressed: busy ? null : submit,
            child: Text(
              busy
                  ? 'Saving demo…'
                  : error == null
                  ? 'Submit demo application'
                  : 'Retry demo submission',
            ),
          ),
      ],
      children: [
        const DemoNotice(),
        Text(widget.job.company),
        const SizedBox(height: 16),
        if (success)
          const Text(
            'Saved only in this session’s demo. No application was sent and no resume was uploaded. You can find it in My Applications.',
          )
        else ...[
          const Text(
            'Demo candidate (you) • Profile details are not connected. Resume missing: no file will be shared. A resume is not required for this preview.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: note,
            enabled: !busy,
            maxLength: 1000,
            minLines: 4,
            maxLines: 8,
            onChanged: (value) {
              widget.repository.keepNoteDraft(draftKey, value);
              setState(() {});
            },
            decoration: const InputDecoration(
              labelText: 'Cover note (optional)',
              alignLabelWithHint: true,
            ),
          ),
          if (error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (busy) const LinearProgressIndicator(),
        ],
      ],
    ),
  );
}
