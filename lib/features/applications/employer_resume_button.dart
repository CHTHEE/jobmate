import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'employer_applicants_repository.dart';
import 'resume_pdf_opener.dart';

class ApplicationResumeLink {
  ApplicationResumeLink(FunctionResponse response, DateTime requestedAt) {
    if (response.status < 200 || response.status >= 300) {
      throw FunctionException(status: response.status);
    }
    final data = response.data;
    if (data is! Map ||
        data['signed_url'] is! String ||
        data['expires_in'] is! num) {
      throw const FormatException('Invalid resume response');
    }
    final raw = data['signed_url'] as String;
    final parsed = Uri.tryParse(raw);
    final seconds = data['expires_in'] as num;
    if (parsed == null ||
        parsed.scheme != 'https' ||
        !parsed.hasAuthority ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        RegExp(r'\s').hasMatch(raw) ||
        !seconds.isFinite ||
        seconds <= 0 ||
        seconds != seconds.truncateToDouble()) {
      throw const FormatException('Invalid resume response');
    }
    uri = parsed;
    // The deployed signer issues 60-second URLs. Start conservatively before
    // the request and never extend that window based on an unexpected response.
    expiresAt = requestedAt.add(
      Duration(seconds: seconds > 60 ? 60 : seconds.toInt()),
    );
  }
  late final Uri uri;
  late final DateTime expiresAt;
}

class EmployerResumeButton extends StatefulWidget {
  const EmployerResumeButton({
    super.key,
    required this.repository,
    required this.applicant,
    this.opener,
    this.now,
  });
  final EmployerApplicantsRepository repository;
  final JobApplicant applicant;
  final ResumePdfOpener? opener;
  final DateTime Function()? now;
  @override
  State<EmployerResumeButton> createState() => _EmployerResumeButtonState();
}

class _EmployerResumeButtonState extends State<EmployerResumeButton> {
  late final opener = widget.opener ?? createResumePdfOpener();
  late final now = widget.now ?? DateTime.now;
  late final String? actor;
  late final Object? company;
  ApplicationResumeLink? link;
  ResumePdfWindow? window;
  bool busy = false, fallback = false;
  String? error;
  bool get valid =>
      mounted &&
      widget.applicant.resumeId != null &&
      widget.repository.active &&
      widget.repository.source.userId == actor &&
      widget.repository.context?.access.company?['company_id'] == company &&
      widget.repository.applicants.any(
        (a) =>
            a.id == widget.applicant.id &&
            a.resumeId == widget.applicant.resumeId,
      );

  @override
  void initState() {
    super.initState();
    // Capture the account/company before any request can start.
    actor = widget.repository.source.userId;
    company = widget.repository.context?.access.company?['company_id'];
    widget.repository.addListener(changed);
  }

  void changed() {
    if (valid) return;
    window?.close();
    window = null;
    link = null;
    if (mounted) {
      setState(() {
        fallback = false;
        error = null;
      });
    }
  }

  Future<void> view() async {
    if (busy || !valid || widget.repository.updating) return;
    // Must happen synchronously within the click, before the first await.
    final reserved = opener.isWeb ? opener.reserve() : null;
    window = reserved;
    setState(() {
      busy = true;
      error = null;
      fallback = false;
    });
    try {
      var prepared = link;
      if (prepared == null || !now().isBefore(prepared.expiresAt)) {
        link = null;
        final requestedAt = now();
        final response = await widget.repository.source
            .viewResume(widget.applicant.id)
            .timeout(const Duration(seconds: 30));
        if (!valid) {
          reserved?.close();
          return;
        }
        prepared = ApplicationResumeLink(response, requestedAt);
      }
      if (!valid) {
        reserved?.close();
        return;
      }
      if (!now().isBefore(prepared.expiresAt)) {
        throw const FormatException('Resume link expired');
      }
      link = prepared;
      final opened = opener.isWeb
          ? (reserved?.navigate(prepared.uri) ?? false)
          : await opener.open(prepared.uri);
      if (!valid) {
        reserved?.close();
        link = null;
        return;
      }
      if (!opened) {
        reserved?.close();
        setState(() {
          fallback = opener.isWeb;
          error = opener.isWeb
              ? 'The browser blocked opening the PDF. Use Open PDF to retry.'
              : 'Unable to open the PDF. Check that a PDF viewer or browser is available, then retry.';
        });
      }
    } catch (failure) {
      reserved?.close();
      link = null;
      if (valid) setState(() => error = resumeViewingError(failure));
    } finally {
      window = null;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openFallback() async {
    if (busy || !valid || !opener.isWeb) return;
    final prepared = link;
    if (prepared == null || !now().isBefore(prepared.expiresAt)) {
      await view();
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // Called directly from this fallback click, with no signing await first.
      final opened = await opener.open(prepared.uri);
      if (valid) {
        setState(() {
          fallback = !opened;
          if (!opened) error = 'Allow PDF windows in your browser and retry.';
        });
      }
    } catch (_) {
      if (valid) {
        setState(
          () => error = 'Unable to open the PDF. Allow PDF windows and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    window?.close();
    link = null;
    widget.repository.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: busy || !valid || widget.repository.updating
                ? null
                : view,
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('View Resume'),
          ),
          if (fallback && opener.isWeb)
            TextButton(
              onPressed: busy ? null : openFallback,
              child: const Text('Open PDF'),
            ),
        ],
      ),
      if (error != null)
        Semantics(
          liveRegion: true,
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}

String resumeViewingError(Object error) {
  if (error is FunctionException) {
    return switch (error.status) {
      400 => 'Unable to request this resume. Refresh applicants and retry.',
      401 => 'Your session has expired. Sign in again to view resumes.',
      403 => 'Access denied or this resume is unavailable.',
      404 => 'No resume is attached to this application.',
      _ => 'The resume service is unavailable. Please retry.',
    };
  }
  if (error is FormatException) {
    return 'The resume service returned an invalid or expired link. Please retry.';
  }
  return 'Unable to load the resume. Check your connection and retry.';
}
