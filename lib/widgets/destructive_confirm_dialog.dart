import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:donefirst/theme/app_theme.dart';

/// Modal confirmation for a destructive action. The action only
/// completes when the user types the supplied [confirmPhrase]
/// verbatim — high friction pattern that protects against the
/// "I tapped Delete without reading the warning" footgun.
///
/// Optionally surfaces an extra warning block (e.g. "you have a
/// paired device on this account") above the type-to-confirm
/// field, so callers can put kid-device-specific or
/// session-specific consequences in front of the user without
/// having to inline a custom dialog each time.
///
/// The widget returns a `Future<bool?>` — true means the user
/// confirmed and typed the phrase, false means they cancelled,
/// null means the dialog was dismissed by tapping outside
/// (treated like cancel by callers).
/// (The angle-brackets in the class doc above were tripping
/// `unintended_html_in_doc_comment` — kept the typed-shape text
/// in plain prose elsewhere.)
///
/// confirmed and typed the phrase, false means they cancelled,
/// null means the dialog was dismissed by tapping outside
/// (treated like cancel by callers).
class DestructiveConfirmDialog extends StatefulWidget {
  final String title;
  final String description;
  final String confirmPhrase;
  final String confirmButtonLabel;
  final String? warningText;
  final IconData? warningIcon;

  const DestructiveConfirmDialog({
    super.key,
    required this.title,
    required this.description,
    required this.confirmPhrase,
    this.confirmButtonLabel = 'Delete',
    this.warningText,
    this.warningIcon,
  });

  /// Convenience that shows the dialog and returns a `Future<bool>`.
  /// `false` is returned for both Cancel and outside-tap dismiss —
  /// callers don't usually need to distinguish.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String description,
    required String confirmPhrase,
    String confirmButtonLabel = 'Delete',
    String? warningText,
    IconData? warningIcon,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => DestructiveConfirmDialog(
        title: title,
        description: description,
        confirmPhrase: confirmPhrase,
        confirmButtonLabel: confirmButtonLabel,
        warningText: warningText,
        warningIcon: warningIcon,
      ),
    );
    return result ?? false;
  }

  @override
  State<DestructiveConfirmDialog> createState() =>
      _DestructiveConfirmDialogState();
}

class _DestructiveConfirmDialogState
    extends State<DestructiveConfirmDialog> {
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
  }

  void _onChange() {
    final ok = _controller.text.trim() == widget.confirmPhrase;
    if (ok != _matches) {
      setState(() => _matches = ok);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.description),
            if (widget.warningText != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warnFill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warnBd),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      widget.warningIcon ?? LucideIcons.alertTriangle,
                      size: 16,
                      color: AppColors.warn,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.warningText!,
                        style: AppText.body(size: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Type ${widget.confirmPhrase} to confirm:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.confirmPhrase,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                if (_matches) {
                  Navigator.of(context).pop(true);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _matches
              ? () => Navigator.of(context).pop(true)
              : null,
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          child: Text(widget.confirmButtonLabel),
        ),
      ],
    );
  }
}
