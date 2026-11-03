import 'package:flutter/material.dart';

/// Returns a trimmed comment, or null when the administrator cancels.
class CompanyRejectionDialog extends StatefulWidget {
  const CompanyRejectionDialog({
    super.key,
    this.approve = false,
    this.logo = false,
  });
  final bool approve;
  final bool logo;

  @override
  State<CompanyRejectionDialog> createState() => _CompanyRejectionDialogState();
}

class _CompanyRejectionDialogState extends State<CompanyRejectionDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.approve
          ? (widget.logo
                ? 'Approve company logo?'
                : 'Approve company application?')
          : (widget.logo
                ? 'Reject company logo'
                : 'Reject company application'),
    ),
    scrollable: true,
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.approve
                ? (widget.logo
                      ? 'The proposed image will replace the current company photo. Company verification and job permissions stay unchanged. A review comment is optional.'
                      : 'Confirm that the submitted company details and supporting document are acceptable. A review comment is optional.')
                : 'Explain what needs to be corrected. The company owner will see this reason in their company profile and notification.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            decoration: InputDecoration(
              labelText: widget.approve
                  ? 'Review comment (optional)'
                  : 'Rejection reason',
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              final reason = (value ?? '').trim();
              if (!widget.approve && reason.isEmpty) {
                return 'Enter a reason to continue.';
              }
              if (reason.runes.length > 2000) {
                return 'Use 2000 characters or fewer.';
              }
              return null;
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState!.validate()) {
            Navigator.of(context).pop(_controller.text.trim());
          }
        },
        child: Text(widget.approve ? 'Approve' : 'Reject'),
      ),
    ],
  );
}
