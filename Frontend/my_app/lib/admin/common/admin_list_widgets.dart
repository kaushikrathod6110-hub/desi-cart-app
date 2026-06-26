import 'package:flutter/material.dart';

class PieSegment {
  final String label;
  final int value;
  PieSegment({required this.label, required this.value});
}

class AdminResponsiveSection extends StatelessWidget {
  final int total;
  final List<PieSegment> segments;

  const AdminResponsiveSection({
    super.key,
    required this.total,
    required this.segments,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;
        final chartSize = isCompact ? 220.0 : 240.0;

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: SizedBox(
                  width: chartSize,
                  height: chartSize,
                  child: AdminPieChart(total: total, segments: segments),
                ),
              ),
              const SizedBox(height: 18),
              AdminLegend(total: total, segments: segments),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: chartSize,
              height: chartSize,
              child: AdminPieChart(total: total, segments: segments),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: AdminLegend(total: total, segments: segments),
            ),
          ],
        );
      },
    );
  }
}

class AdminPieChart extends StatelessWidget {
  final int total;
  final List<PieSegment> segments;

  const AdminPieChart({super.key, required this.total, required this.segments});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PiePainter(total: total, segments: segments),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Total\n$total',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  final int total;
  final List<PieSegment> segments;

  _PiePainter({required this.total, required this.segments});

  final List<Color> _colors = const [
    Color(0xFF4CAF50),
    Color(0xFF8BC34A),
    Color(0xFFF44336),
    Color(0xFFFF7961),
    Color(0xFF9E9E9E),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide / 2) - 10;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.butt;

    paint.color = Colors.grey.shade300;
    canvas.drawCircle(center, radius, paint);

    if (total <= 0) return;

    double startAngle = -1.5708;
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (seg.value <= 0) continue;

      final sweep = (seg.value / total) * 6.28318;
      paint.color = _colors[i % _colors.length];

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        paint,
      );

      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) {
    return oldDelegate.total != total ||
        oldDelegate.segments.map((e) => e.value).join(',') !=
            segments.map((e) => e.value).join(',');
  }
}

class AdminLegend extends StatelessWidget {
  final int total;
  final List<PieSegment> segments;

  const AdminLegend({super.key, required this.total, required this.segments});

  final List<Color> _colors = const [
    Color(0xFF4CAF50),
    Color(0xFF8BC34A),
    Color(0xFFF44336),
    Color(0xFFFF7961),
    Color(0xFF9E9E9E),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(segments.length, (i) {
        final seg = segments[i];
        final pct = total == 0 ? 0.0 : ((seg.value / total) * 100);

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 2),
                color: _colors[i % _colors.length],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  seg.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${seg.value} (${pct.toStringAsFixed(1)}%)',
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class AdminStatsChips extends StatelessWidget {
  final int total;
  final int active;
  final int inactive;
  final int newCount;
  final int oldCount;

  const AdminStatsChips({
    super.key,
    required this.total,
    required this.active,
    required this.inactive,
    required this.newCount,
    required this.oldCount,
  });

  @override
  Widget build(BuildContext context) {
    Chip chip(String label, int value) => Chip(label: Text('$label: $value'));

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        chip('Total', total),
        chip('Active', active),
        chip('Inactive', inactive),
        chip('New (30d)', newCount),
        chip('Old', oldCount),
      ],
    );
  }
}

class StatusActionTrailing extends StatelessWidget {
  final bool isActive;
  final String activeLabel;
  final String inactiveLabel;
  final String actionActiveText;
  final String actionInactiveText;
  final VoidCallback? onPressed;
  final bool compact;

  const StatusActionTrailing({
    super.key,
    required this.isActive,
    this.activeLabel = 'Active',
    this.inactiveLabel = 'Inactive',
    this.actionActiveText = 'Block',
    this.actionInactiveText = 'Unblock',
    required this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isActive ? Colors.green : Colors.red;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
      compact ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: statusColor.withValues(alpha: 0.5)),
          ),
          child: Text(
            isActive ? activeLabel : inactiveLabel,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: onPressed,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(isActive ? actionActiveText : actionInactiveText),
            ),
          ),
        ),
      ],
    );
  }
}

class AdminItemCard extends StatelessWidget {
  final Widget? leading;
  final String title;
  final List<String> lines;
  final Widget trailing;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  const AdminItemCard({
    super.key,
    this.leading,
    required this.title,
    required this.lines,
    required this.trailing,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      margin: margin,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 700;

            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                ...lines.map(
                      (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            );

            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (leading != null) ...[
                        leading!,
                        const SizedBox(width: 12),
                      ],
                      Expanded(child: info),
                    ],
                  ),
                  const SizedBox(height: 12),
                  trailing,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 12),
                ],
                Expanded(child: info),
                const SizedBox(width: 12),
                trailing,
              ],
            );
          },
        ),
      ),
    );

    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: card,
    );
  }
}

class AdminMiniStatTile extends StatelessWidget {
  final String label;
  final String value;

  const AdminMiniStatTile({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

Widget statCard(String title, String value, IconData icon) {
  return buildDashboardStatCard(
    title: title,
    value: value,
    icon: icon,
  );
}

Widget buildDashboardStatCard({
  required String title,
  required String value,
  required IconData icon,
  VoidCallback? onTap,
}) {
  return Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          width: 190,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                ),
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget alertChip(String label, int value, IconData icon, {VoidCallback? onTap}) {
  final chip = Chip(
    avatar: Icon(icon, size: 18),
    label: Text('$label: $value'),
  );
  if (onTap == null) return chip;
  return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: chip);
}