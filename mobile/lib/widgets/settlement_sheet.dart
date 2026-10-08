import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../formatting/diary_format.dart';
import '../models/day.dart';
import '../theme/shift_theme.dart';

/// A receipt-like view of the server's daily settlement.
class SettlementSheet extends StatefulWidget {
  const SettlementSheet({required this.summary, super.key});

  final DaySummary summary;

  @override
  State<SettlementSheet> createState() => _SettlementSheetState();
}

class _SettlementSheetState extends State<SettlementSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal;
  double _dragOrigin = 0;
  bool _dragActive = false;
  bool _pointerCancelled = false;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && _reveal.isAnimating) {
      _reveal.value = _open ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  void _settle(bool open) {
    setState(() => _open = open);
    final target = open ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = target;
    } else {
      _reveal.animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: const Cubic(.2, .7, .2, 1),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth <= 318 ||
            MediaQuery.textScalerOf(context).scale(16) >= 24;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: ShiftColors.foreground.withValues(alpha: .05),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: ShiftColors.hero,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          Text(
                            'На руки',
                            style: TextStyle(
                              color: ShiftColors.heroInk,
                              fontSize: 13.44,
                              fontWeight: FontWeight.w500,
                              letterSpacing: .3,
                            ),
                          ),
                          Text(
                            'ИТОГ ДНЯ',
                            style: TextStyle(
                              color: ShiftColors.heroInk,
                              fontSize: 10,
                              fontFamily: 'monospace',
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 22),
                        child: _NetAmount(amount: summary.netIncome),
                      ),
                      _MetricPair(
                        stacked: stacked,
                        left: _Metric(
                          label: 'Выручка',
                          amount: summary.revenue,
                          dark: true,
                        ),
                        right: _Metric(
                          label: 'Комиссия',
                          amount: summary.commission,
                          dark: true,
                          trailing: !stacked,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _reveal,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _seam(),
                    ClipRect(
                      child: SizeTransition(
                        key: const Key('calculation-fold'),
                        sizeFactor: _reveal,
                        alignment: Alignment.topCenter,
                        child: Offstage(
                          offstage: _reveal.value == 0,
                          child: ExcludeSemantics(
                            excluding: _reveal.value < 1,
                            child: IgnorePointer(
                              ignoring: _reveal.value < 1,
                              child: _Calculation(summary: summary),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: ShiftColors.surface,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
                  child: _MetricPair(
                    stacked: stacked,
                    left: _Metric(
                      label: 'Наличные',
                      amount: summary.cash,
                      icon: Icons.payments_outlined,
                    ),
                    right: _Metric(
                      label: 'Карта',
                      amount: summary.card,
                      icon: Icons.credit_card_outlined,
                      trailing: !stacked,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _seam() {
    return CustomPaint(
      foregroundPainter: const _SeamPainter(),
      child: Material(
        color: ShiftColors.hero,
        child: Semantics(
          button: true,
          expanded: _open,
          label: _open ? 'Скрыть расчёт' : 'Показать расчёт',
          value: _open ? 'Раскрыт' : 'Свёрнут',
          onTap: () => _settle(!_open),
          child: Listener(
            onPointerDown: (_) => _pointerCancelled = false,
            onPointerCancel: (_) => _pointerCancelled = true,
            child: GestureDetector(
              dragStartBehavior: DragStartBehavior.down,
              onVerticalDragStart: (_) {
                _dragActive = true;
                _dragOrigin = _open ? 1 : 0;
                _reveal.stop();
              },
              onVerticalDragUpdate: (details) {
                _reveal.value = (_reveal.value + details.delta.dy / 90).clamp(
                  0.0,
                  1.0,
                );
              },
              onVerticalDragEnd: (_) {
                _dragActive = false;
                _settle(
                  _pointerCancelled ? _dragOrigin == 1 : _reveal.value > .35,
                );
              },
              onVerticalDragCancel: () {
                if (!_dragActive) return;
                _dragActive = false;
                _settle(_dragOrigin == 1);
              },
              child: InkWell(
                key: const Key('calculation-toggle'),
                excludeFromSemantics: true,
                onTap: () => _settle(!_open),
                hoverColor: ShiftColors.accentHover,
                focusColor: ShiftColors.accent,
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _open ? 'Свернуть расчёт' : 'Развернуть расчёт',
                            style: const TextStyle(
                              color: ShiftColors.surface,
                              fontSize: 11.2,
                              fontWeight: FontWeight.w500,
                              letterSpacing: .25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 32,
                          height: 20,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: ShiftColors.surface.withValues(alpha: .6),
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Transform.rotate(
                            angle: _reveal.value * .7853981633974483,
                            child: const Icon(
                              Icons.add,
                              color: ShiftColors.surface,
                              size: 17,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NetAmount extends StatelessWidget {
  const _NetAmount({required this.amount});

  final BigInt amount;

  @override
  Widget build(BuildContext context) {
    final money = formatMoney(amount);
    final grouped = money.substring(0, money.length - 2);
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;
    final size = grouped.length > 9
        ? 36.8
        : largeText
        ? 35.2
        : 64.8;
    return Text.rich(
      key: const Key('net-amount'),
      TextSpan(
        children: [
          TextSpan(text: '$grouped '),
          WidgetSpan(
            alignment: PlaceholderAlignment.top,
            child: ExcludeSemantics(
              child: Text(
                '₸',
                style: TextStyle(
                  color: ShiftColors.surface,
                  fontSize: size * .42,
                  fontWeight: FontWeight.w400,
                  height: 1.6,
                  letterSpacing: -.4,
                ),
              ),
            ),
          ),
        ],
      ),
      semanticsLabel: money,
      style: TextStyle(
        color: ShiftColors.surface,
        fontSize: size,
        height: 1.05,
        fontWeight: FontWeight.w400,
        letterSpacing: -size * .045,
      ),
    );
  }
}

class _MetricPair extends StatelessWidget {
  const _MetricPair({
    required this.stacked,
    required this.left,
    required this.right,
  });

  final bool stacked;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, const SizedBox(height: 16), right],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 16),
        Expanded(child: right),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.amount,
    this.dark = false,
    this.trailing = false,
    this.icon,
  });

  final String label;
  final BigInt amount;
  final bool dark;
  final bool trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: trailing
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: trailing ? WrapAlignment.end : WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            if (icon != null) Icon(icon, size: 15, color: ShiftColors.muted),
            Text(
              label,
              style: TextStyle(
                color: dark ? ShiftColors.heroInk : ShiftColors.muted,
                fontSize: dark ? 11.52 : 11.04,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          formatMoney(amount),
          textAlign: trailing ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            color: dark ? ShiftColors.surface : ShiftColors.foreground,
            fontSize: dark ? 16.64 : 18.08,
            fontWeight: FontWeight.w600,
            letterSpacing: dark ? 0 : -.6,
          ),
        ),
      ],
    );
  }
}

class _Calculation extends StatelessWidget {
  const _Calculation({required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('calculation-equation'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(color: ShiftColors.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Выручка − комиссия = на руки',
            style: TextStyle(
              color: ShiftColors.muted,
              fontSize: 11.68,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            label:
                '${formatMoney(summary.revenue)} минус '
                '${formatMoney(summary.commission)} равно '
                '${formatMoney(summary.netIncome)}',
            child: ExcludeSemantics(
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(formatMoney(summary.revenue)),
                  const Text('−'),
                  Text(formatMoney(summary.commission)),
                  const Text('='),
                  Text(
                    formatMoney(summary.netIncome),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          CustomPaint(
            painter: _DashedLinePainter(ShiftColors.border),
            size: const Size(double.infinity, 1),
          ),
        ],
      ),
    );
  }
}

class _SeamPainter extends CustomPainter {
  const _SeamPainter();

  @override
  void paint(Canvas canvas, Size size) {
    _DashedLinePainter(
      ShiftColors.surface.withValues(alpha: .35),
    ).paint(canvas, Size(size.width, 1));
    final paint = Paint()..color = ShiftColors.background;
    canvas.drawCircle(Offset(0, 0), 7, paint);
    canvas.drawCircle(Offset(size.width, 0), 7, paint);
  }

  @override
  bool shouldRepaint(_SeamPainter oldDelegate) => false;
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, .5),
        Offset((x + 4).clamp(0, size.width), .5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
