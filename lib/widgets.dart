import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'strings.dart';

import 'theme.dart';

export 'theme.dart' show brandColor, Tone;

String errorText(BuildContext context, Object error) {
  if (error is ApiException && error.status == 0) return S.of(context).t('network');
  return error.toString();
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// "2026-10-05T09:30:00+03:00" -> "2026-10-05 09:30" in the phone's time zone.
String shortDate(dynamic iso) {
  final parsed = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  if (parsed == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} ${two(parsed.hour)}:${two(parsed.minute)}';
}

/// "5m", "3h", "2d" or the date for older items; the list cards use it.
String relativeDate(BuildContext context, dynamic iso) {
  final parsed = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  if (parsed == null) return '';
  final s = S.of(context);
  final diff = DateTime.now().difference(parsed);
  if (diff.inMinutes < 1) return s.t('now');
  if (diff.inMinutes < 60) return '${diff.inMinutes}${s.t('min_short')}';
  if (diff.inHours < 24) return '${diff.inHours}${s.t('hour_short')}';
  if (diff.inDays < 7) return '${diff.inDays}${s.t('day_short')}';
  return shortDate(iso).substring(0, 10);
}

Color priorityColor(String? priority) {
  switch (priority) {
    case 'urgent':
      return Tone.danger;
    case 'high':
      return Tone.warning;
    case 'medium':
      return Tone.info;
    default:
      return Tone.neutral;
  }
}

/// Open is "new, not started" (blue), not an alarm; urgency is shown by the priority pill.
Color statusColor(String? status) {
  switch (status) {
    case 'open':
      return Tone.info;
    case 'in_progress':
      return Tone.warning;
    case 'resolved':
      return Tone.success;
    default:
      return Tone.neutral;
  }
}

/// Small rounded label, tinted with its colour.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon});

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700, height: 1.4)),
        ],
      ),
    );
  }
}

/// Label on the left, value on the right; hidden when the value is empty.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.icon});

  final String label;
  final dynamic value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
          ],
          SizedBox(
            width: 104,
            child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          ),
          Expanded(child: SelectableText(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

/// Section heading with an optional trailing action ("See all").
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 20, 0, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

/// Photo or initials in a circle.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.url, this.size = 48, this.onBrand = false});

  final String name;
  final String? url;
  final double size;

  /// Shown on the brand gradient: white ring and translucent background.
  final bool onBrand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.take(2).map((p) => p.characters.first).join();

    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: onBrand ? Colors.white.withValues(alpha: 0.2) : scheme.primary.withValues(alpha: 0.12),
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          color: onBrand ? Colors.white : scheme.primary,
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: onBrand ? Colors.white.withValues(alpha: 0.7) : scheme.outlineVariant, width: 2),
      ),
      child: ClipOval(
        child: url == null || url!.isEmpty
            ? fallback
            : Image.network(
                url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}

/// One row in a list: tinted icon, title, subtitle, chips, time. Unread rows get
/// a bolder title, a tinted icon and a dot next to the time.
class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.chips = const [],
    this.trailing,
    this.unread = false,
    this.accent,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> chips;
  final String? trailing;
  final bool unread;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;
    final iconColor = unread ? color : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: unread ? 0.13 : 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                height: 1.4,
                                color: scheme.onSurface,
                                fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (trailing != null || unread) ...[
                            const SizedBox(width: 10),
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (trailing != null)
                                    Text(
                                      trailing!,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: unread ? color : scheme.onSurfaceVariant,
                                        fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                                      ),
                                    ),
                                  if (unread) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.45),
                        ),
                      ],
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 4, children: chips),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chevron should point "forward": right in LTR, left in RTL.
TextDirection textDirectionFor(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl ? TextDirection.rtl : TextDirection.ltr;

/// One counter on the home "attention" card: icon, number and label.
class StatCell extends StatelessWidget {
  const StatCell({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quiet = value == 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: (quiet ? scheme.outline : color).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: quiet ? scheme.outline : color),
                ),
                const SizedBox(width: 8),
                Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: quiet ? scheme.outline : scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shortcut in the home grid: tinted icon over a two-line label.
class ActionTile extends StatelessWidget {
  const ActionTile({super.key, required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(17)),
              child: Icon(icon, color: c, size: 24),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lays children out in [columns] equal columns; each row is as tall as its
/// content, so labels never get clipped (a fixed-ratio grid did, and would
/// again with a larger system font).
class ColumnsWrap extends StatelessWidget {
  const ColumnsWrap({super.key, required this.columns, required this.children, this.spacing = 0});

  final int columns;
  final double spacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final child in children) SizedBox(width: width, child: child)],
        );
      },
    );
  }
}

/// Top card of a detail screen (ticket, complaint, message): pills, title,
/// the full text and a date line.
class DetailHeader extends StatelessWidget {
  const DetailHeader({super.key, required this.pills, this.title, this.body, this.meta});

  final List<Widget> pills;
  final String? title;
  final String? body;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 6, runSpacing: 6, children: pills),
            if (title != null && title!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(title!, style: Theme.of(context).textTheme.titleLarge),
            ],
            if (body != null && body!.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText(body!, style: TextStyle(fontSize: 15, height: 1.7, color: scheme.onSurface)),
            ],
            if (meta != null && meta!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(meta!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One step in a vertical history (ticket updates): dot, connecting line, text.
class TimelineEntry extends StatelessWidget {
  const TimelineEntry({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.date,
    this.color,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String text;
  final String date;
  final Color? color;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(icon, size: 16, color: c),
                ),
                if (!last) Expanded(child: Container(width: 2, color: scheme.outlineVariant.withValues(alpha: 0.6))),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                      Text(date, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  if (text.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SelectableText(text, style: TextStyle(height: 1.6, color: scheme.onSurface)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled group of form fields on its own card (the ticket form's steps).
class FieldGroup extends StatelessWidget {
  const FieldGroup({super.key, required this.title, required this.children, this.icon, this.hint});

  final String title;
  final IconData? icon;
  final String? hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
              ],
            ),
            if (hint != null) ...[
              const SizedBox(height: 2),
              Text(hint!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Selectable tile with an icon (ticket categories, urgency).
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color,
  });

  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? c.withValues(alpha: 0.1) : Theme.of(context).inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? c : Colors.transparent, width: 1.6),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: icon == null ? 11 : 12, horizontal: 6),
            // Equal tiles in a row even when one label takes two lines.
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: icon == null ? 0 : 74),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: selected ? c : scheme.onSurfaceVariant, size: 24),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    label,
                    maxLines: icon == null ? 1 : 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      height: 1.3,
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? c : scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Looks like a filled field; tapping opens a picker. Shows the choice and a second line.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.value,
    this.detail,
    this.errorText,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final String? value;
  final String? detail;
  final String? errorText;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = value == null || value!.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Theme.of(context).inputDecorationTheme.fillColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: errorText != null ? BorderSide(color: scheme.error, width: 1.2) : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, color: empty ? scheme.onSurfaceVariant : scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          empty ? label : value!,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: empty ? FontWeight.w500 : FontWeight.w700,
                            color: empty ? scheme.onSurfaceVariant : scheme.onSurface,
                          ),
                        ),
                        if (!empty && detail != null && detail!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            detail!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant, height: 1.4),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (loading)
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Icon(Icons.unfold_more_rounded, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 14, top: 6),
            child: Text(errorText!, style: TextStyle(color: scheme.error, fontSize: 12)),
          ),
      ],
    );
  }
}

/// A settings-style row: icon, title, optional value, chevron.
class MenuRow extends StatelessWidget {
  const MenuRow({super.key, required this.icon, required this.title, this.value, this.onTap, this.color});

  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color ?? scheme.primary),
            const SizedBox(width: 14),
            Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: c))),
            if (value != null)
              Flexible(
                child: Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 20, color: scheme.outline, textDirection: textDirectionFor(context)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Grey placeholder rows shown while a list loads.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.rows = 6});

  final int rows;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_controller),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: widget.rows,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Container(
            height: 84,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(13))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(height: 12, width: 180, decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 8),
                    Container(height: 10, width: 120, decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6))),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Friendly "nothing here" block.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, this.icon = Icons.inbox_outlined, this.text});

  final IconData icon;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: Icon(icon, size: 38, color: scheme.primary.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 16),
          Text(text ?? S.of(context).t('empty'),
              textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Loads one record and shows loading / error / content.
class Loader extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});

  final Future<Map<String, dynamic>> Function() load;
  final Widget Function(BuildContext context, Map<String, dynamic> data, VoidCallback reload) builder;

  @override
  State<Loader> createState() => _LoaderState();
}

class _LoaderState extends State<Loader> {
  late Future<Map<String, dynamic>> _future = widget.load();

  void _reload() => setState(() => _future = widget.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SkeletonList(rows: 4);
        }
        if (snapshot.hasError) {
          return ErrorView(error: snapshot.error!, onRetry: _reload);
        }
        return widget.builder(context, snapshot.data!, _reload);
      },
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 44, color: scheme.outline),
            const SizedBox(height: 12),
            Text(errorText(context, error), textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(S.of(context).t('retry')),
            ),
          ],
        ),
      ),
    );
  }
}

/// A paginated, pull-to-refresh list backed by one API endpoint
/// that answers with { data: [...], meta: { current_page, last_page } }.
class PagedList extends StatefulWidget {
  const PagedList({
    super.key,
    required this.path,
    required this.itemBuilder,
    this.query = const {},
    this.header,
    this.emptyIcon = Icons.inbox_outlined,
  });

  final String path;
  final Map<String, String> query;
  final Widget? header;
  final IconData emptyIcon;
  final Widget Function(BuildContext context, Map<String, dynamic> item, VoidCallback refresh) itemBuilder;

  @override
  State<PagedList> createState() => PagedListState();
}

class PagedListState extends State<PagedList> {
  final List<Map<String, dynamic>> _items = [];
  int _page = 0;
  int _lastPage = 1;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void didUpdateWidget(PagedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.query.toString() != widget.query.toString()) {
      refresh();
    }
  }

  Future<void> refresh() async {
    _page = 0;
    _lastPage = 1;
    await _loadMore(reset: true);
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final body = await api.get(widget.path, {...widget.query, 'page': '${_page + 1}'});
      final rows = (body['data'] as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(rows);
        _page = (body['meta']?['current_page'] as int?) ?? _page + 1;
        _lastPage = (body['meta']?['last_page'] as int?) ?? _page;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    if (_items.isEmpty && _loading) {
      return const SkeletonList();
    }
    if (_items.isEmpty && _error != null) {
      return ErrorView(error: _error!, onRetry: refresh);
    }

    final hasMore = _page < _lastPage;
    final headerCount = widget.header == null ? 0 : 1;

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 6, bottom: 96),
        itemCount: headerCount + (_items.isEmpty ? 1 : _items.length + (hasMore ? 1 : 0)),
        itemBuilder: (context, index) {
          if (headerCount == 1 && index == 0) return widget.header!;
          final i = index - headerCount;

          if (_items.isEmpty) {
            return EmptyState(icon: widget.emptyIcon);
          }
          if (i >= _items.length) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : TextButton(onPressed: _loadMore, child: Text(s.t('more'))),
              ),
            );
          }
          return widget.itemBuilder(context, _items[i], refresh);
        },
      ),
    );
  }
}

/// Segmented filter above a list, padded to match the cards.
class FilterBar extends StatelessWidget {
  const FilterBar({super.key, required this.segments, required this.selected, required this.onChanged});

  final Map<String, String> segments;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Pills in a scrolling row: long labels ("needs follow-up") stay on one line.
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        children: [
          for (final entry in segments.entries)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Material(
                color: entry.key == selected ? scheme.primary : Theme.of(context).inputDecorationTheme.fillColor,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => onChanged(entry.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: entry.key == selected ? FontWeight.w700 : FontWeight.w500,
                        color: entry.key == selected ? scheme.onPrimary : scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Debounced search box above a list.
class SearchField extends StatefulWidget {
  const SearchField({super.key, required this.onChanged, this.hint});

  final ValueChanged<String> onChanged;
  final String? hint;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => widget.onChanged(value.trim()));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _controller,
        onChanged: _changed,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: widget.hint ?? S.of(context).t('search'),
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _controller.clear();
                    _changed('');
                  },
                ),
        ),
      ),
    );
  }
}

/// Searchable single-choice list fetched from the API, with an optional "create" row.
/// `load` answers a search text with rows; `label` renders a row.
Future<Map<String, dynamic>?> showPickerSheet(
  BuildContext context, {
  required String title,
  required Future<List<Map<String, dynamic>>> Function(String search) load,
  required String Function(Map<String, dynamic> row) label,
  String Function(Map<String, dynamic> row)? sublabel,
  Future<Map<String, dynamic>?> Function(String search)? onCreate,
  String? createLabel,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => _PickerBody(
        title: title,
        load: load,
        label: label,
        sublabel: sublabel,
        onCreate: onCreate,
        createLabel: createLabel,
        scroll: scroll,
      ),
    ),
  );
}

class _PickerBody extends StatefulWidget {
  const _PickerBody({
    required this.title,
    required this.load,
    required this.label,
    required this.scroll,
    this.sublabel,
    this.onCreate,
    this.createLabel,
  });

  final String title;
  final Future<List<Map<String, dynamic>>> Function(String search) load;
  final String Function(Map<String, dynamic> row) label;
  final String Function(Map<String, dynamic> row)? sublabel;
  final Future<Map<String, dynamic>?> Function(String search)? onCreate;
  final String? createLabel;
  final ScrollController scroll;

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  List<Map<String, dynamic>> _rows = [];
  String _search = '';
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String search) async {
    setState(() {
      _search = search;
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.load(search);
      if (mounted && search == _search) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        ),
        SearchField(onChanged: _load),
        if (widget.onCreate != null && _search.isNotEmpty)
          ListTile(
            leading: Icon(Icons.add_circle_outline, color: scheme.primary),
            title: Text('${widget.createLabel ?? S.of(context).t('add')}: "$_search"', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
            onTap: () async {
              final created = await widget.onCreate!(_search);
              if (created != null && context.mounted) Navigator.of(context).pop(created);
            },
          ),
        Expanded(
          child: _error != null
              ? ErrorView(error: _error!, onRetry: () => _load(_search))
              : _loading && _rows.isEmpty
                  ? const SkeletonList(rows: 5)
                  : _rows.isEmpty
                      ? const EmptyState(icon: Icons.search_off)
                      : ListView.separated(
                          controller: widget.scroll,
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const Divider(indent: 20, endIndent: 20),
                          itemBuilder: (context, index) {
                            final row = _rows[index];
                            final sub = widget.sublabel?.call(row);
                            return ListTile(
                              title: Text(widget.label(row)),
                              subtitle: sub == null || sub.isEmpty ? null : Text(sub),
                              onTap: () => Navigator.of(context).pop(row),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

/// Bottom sheet that hosts a form; sized to the keyboard.
Future<T?> showFormSheet<T>(BuildContext context, {required String title, required Widget child}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    ),
  );
}
