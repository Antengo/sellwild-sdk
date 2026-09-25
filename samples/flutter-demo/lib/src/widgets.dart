import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:url_launcher/url_launcher.dart';

/// Gives [child] the e2e id [id] (contracts/e2e/ids.json) as its Semantics
/// identifier: the accessibilityIdentifier on iOS and the resource-id on
/// Android, which is what Maestro's `id:` matches. The node is a container,
/// so the id is not merged into a parent's node. The text of [child] becomes
/// the node's label; [label] names a container that has no text of its own.
class E2EId extends StatelessWidget {
  const E2EId(this.id, {super.key, required this.child, this.label});

  final String id;
  final String? label;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Semantics(container: true, identifier: id, label: label, child: child);
}

/// The title block at the top of each screen.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(detail, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// One line of status text under a header.
class StatusLine extends StatelessWidget {
  const StatusLine(this.id, this.text, {super.key});

  final String id;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: E2EId(
            id,
            child: Text(text, style: Theme.of(context).textTheme.labelSmall),
          ),
        ),
      );
}

/// "320x50": a size in logical pixels (points on iOS, dp on Android).
String sizeLabel(Size size) => '${size.width.round()}x${size.height.round()}';

/// One ad slot: a title, the ad in a box of a fixed size, and the box's
/// measured size under it. Test ads may not fill; the box keeps its size
/// either way.
class AdSlot extends StatefulWidget {
  const AdSlot({
    super.key,
    required this.title,
    required this.detail,
    required this.id,
    required this.sizeId,
    required this.label,
    required this.width,
    required this.height,
    required this.child,
  });

  final String title;
  final String detail;
  final String id;
  final String sizeId;
  final String label;
  final double width;
  final double height;
  final Widget child;

  @override
  State<AdSlot> createState() => _AdSlotState();
}

class _AdSlotState extends State<AdSlot> {
  final _box = GlobalKey();
  String _measured = '0x0';

  void _measure(Duration _) {
    final size = _box.currentContext?.size;
    if (!mounted || size == null) return;
    final measured = sizeLabel(size);
    if (measured != _measured) setState(() => _measured = measured);
  }

  @override
  Widget build(BuildContext context) {
    // After layout, the box has its size.
    SchedulerBinding.instance.addPostFrameCallback(_measure);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: theme.textTheme.titleMedium),
          Text(widget.detail, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Center(
            child: E2EId(
              widget.id,
              label: widget.label,
              child: Container(
                key: _box,
                width: widget.width,
                height: widget.height,
                color: theme.colorScheme.surfaceContainerHighest,
                child: widget.child,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: E2EId(
              widget.sizeId,
              child: Text(_measured, style: theme.textTheme.labelSmall),
            ),
          ),
        ],
      ),
    );
  }
}

/// A surface the Flutter SDK does not have, said plainly.
class MissingSurface extends StatelessWidget {
  const MissingSurface({super.key, required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          Text(detail, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Opens [link] in the browser. A link that does not parse or cannot open
/// is shown in a snack bar; the app goes on.
Future<void> openLink(BuildContext context, String? link) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = link == null ? null : Uri.tryParse(link);
  var opened = false;
  if (uri != null) {
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception catch (e) {
      debugPrint('[Sample] could not open $uri: $e');
    }
  }
  if (!opened) {
    messenger.showSnackBar(const SnackBar(content: Text('Cannot open it')));
  }
}
