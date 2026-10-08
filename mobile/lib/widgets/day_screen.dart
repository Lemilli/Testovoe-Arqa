import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/day_api.dart';
import '../formatting/diary_format.dart';
import '../models/day.dart';
import '../models/diary_date.dart';
import '../state/day_providers.dart';
import '../theme/shift_theme.dart';
import 'settlement_sheet.dart';
import 'trip_form.dart';

class DayScreen extends ConsumerStatefulWidget {
  const DayScreen({super.key});

  @override
  ConsumerState<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends ConsumerState<DayScreen> {
  int _refreshRevision = 0;

  Future<void> _addTrip(
    BuildContext context,
    WidgetRef ref,
    DiaryDate selected,
  ) async {
    final affectedDay = await Navigator.of(context).push<DiaryDate>(
      MaterialPageRoute(builder: (_) => TripForm(initialDate: selected)),
    );
    if (affectedDay == null || !context.mounted) return;
    final currentDay = ref.read(selectedDayProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          affectedDay == currentDay
              ? 'Поездка добавлена'
              : 'Поездка добавлена: ${formatDay(affectedDay)}',
        ),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref, DiaryDate date) async {
    // Even an immediately completed refresh closes the previous calculation.
    setState(() => _refreshRevision++);
    try {
      final pending = ref.refresh(dayProvider(date).future);
      await pending;
    } catch (_) {
      // The provider exposes the error and the screen offers another attempt.
    }
  }

  Future<void> _chooseDate(
    BuildContext context,
    WidgetRef ref,
    DiaryDate selected,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selected.toDateTime,
      firstDate: DiaryDate.first.toDateTime,
      lastDate: DiaryDate.last.toDateTime,
      currentDate: ref.read(todayProvider).toDateTime,
      helpText: 'Выберите день',
    );
    if (picked != null && context.mounted) {
      ref
          .read(selectedDayProvider.notifier)
          .select(DiaryDate.fromDateTime(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedDayProvider);
    final today = ref.watch(todayProvider);
    final day = ref.watch(dayProvider(selected));
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;

    return Scaffold(
      bottomNavigationBar: SafeArea(
        top: false,
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: FilledButton(
                key: const Key('add-trip'),
                onPressed: () => _addTrip(context, ref, selected),
                child: const Row(
                  children: [
                    Expanded(child: Text('Добавить поездку')),
                    SizedBox(width: 12),
                    Icon(Icons.add, size: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      appBar: AppBar(
        toolbarHeight: largeText ? 94 : 66,
        titleSpacing: 24,
        title: const Row(
          children: [
            ExcludeSemantics(
              child: Text(
                '//',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -3,
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Дневник смен',
                style: TextStyle(
                  fontSize: 16.96,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.76,
                  height: 1.14,
                ),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton(
              key: const Key('refresh-day'),
              tooltip: 'Обновить день',
              style: _circleButtonStyle,
              onPressed: day.isLoading ? null : () => _refresh(ref, selected),
              icon: const Icon(Icons.refresh, size: 22),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 840,
            child: Column(
              children: [
                _CalendarDateLockup(
                  selected: selected,
                  today: today,
                  onChoose: () => _chooseDate(context, ref, selected),
                  onPrevious: selected == DiaryDate.first
                      ? null
                      : ref.read(selectedDayProvider.notifier).previous,
                  onNext: selected == DiaryDate.last
                      ? null
                      : ref.read(selectedDayProvider.notifier).next,
                  onToday: () =>
                      ref.read(selectedDayProvider.notifier).select(today),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _refresh(ref, selected),
                    child: CustomScrollView(
                      key: const Key('day-scroll'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: day.when(
                        skipLoadingOnRefresh: false,
                        skipLoadingOnReload: false,
                        loading: () => const [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                            sliver: SliverToBoxAdapter(child: _LoadingDay()),
                          ),
                        ],
                        error: (error, _) => [
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _DayError(
                              message: error is DayApiException
                                  ? error.message
                                  : 'Не удалось загрузить день. Попробуйте ещё раз.',
                              onRetry: () => _refresh(ref, selected),
                            ),
                          ),
                        ],
                        data: (data) => [
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverToBoxAdapter(
                              child: SettlementSheet(
                                // A new server snapshot resets its local fold,
                                // while unrelated rebuilds preserve it.
                                key: ValueKey((
                                  selected,
                                  _refreshRevision,
                                  data,
                                )),
                                summary: data.summary,
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(24, 25, 24, 0),
                            sliver: SliverToBoxAdapter(
                              child: _TripsHeading(
                                count: data.summary.tripCount,
                              ),
                            ),
                          ),
                          if (data.trips.isEmpty)
                            const SliverPadding(
                              padding: EdgeInsets.fromLTRB(24, 24, 24, 32),
                              sliver: SliverToBoxAdapter(child: _EmptyDay()),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              sliver: SliverList.builder(
                                itemCount: data.trips.length,
                                itemBuilder: (context, index) => _TripLedgerRow(
                                  trip: data.trips[index],
                                  last: index == data.trips.length - 1,
                                ),
                              ),
                            ),
                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                        ],
                      ),
                    ),
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

final _circleButtonStyle = IconButton.styleFrom(
  fixedSize: const Size(48, 48),
  padding: EdgeInsets.zero,
  side: const BorderSide(color: ShiftColors.border),
  shape: const CircleBorder(),
);

class _CalendarDateLockup extends StatelessWidget {
  const _CalendarDateLockup({
    required this.selected,
    required this.today,
    required this.onChoose,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final DiaryDate selected;
  final DiaryDate today;
  final VoidCallback onChoose;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onToday;

  static const _months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  static const _weekdays = [
    'понедельник',
    'вторник',
    'среда',
    'четверг',
    'пятница',
    'суббота',
    'воскресенье',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;
        final narrow = constraints.maxWidth <= 350;
        final stacked = narrow || largeText;
        final weekday = _weekdays[selected.toDateTime.weekday - 1];
        final date = TextButton(
          key: const Key('choose-day'),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
            foregroundColor: ShiftColors.foreground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: onChoose,
          child: Semantics(
            label: '${formatDay(selected)}, $weekday',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Text(
                    selected.day.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: largeText
                          ? 32
                          : narrow
                          ? 44.8
                          : 55.2,
                      fontWeight: FontWeight.w400,
                      height: 1.02,
                      letterSpacing: -4,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _months[selected.month - 1],
                          style: TextStyle(
                            fontSize: narrow && !largeText ? 12.8 : 15.04,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${selected.year} · $weekday',
                          style: const TextStyle(
                            fontSize: 11.13,
                            fontWeight: FontWeight.w400,
                            color: ShiftColors.muted,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final arrows = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('previous-day'),
              tooltip: 'Предыдущий день',
              style: _circleButtonStyle,
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              key: const Key('next-day'),
              tooltip: 'Следующий день',
              style: _circleButtonStyle,
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(
            narrow ? 20 : 24,
            10,
            narrow ? 20 : 24,
            15,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stacked) ...[
                date,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: arrows),
              ] else
                Row(
                  children: [
                    Expanded(child: date),
                    const SizedBox(width: 8),
                    arrows,
                  ],
                ),
              if (selected != today)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('today'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: ShiftColors.foreground,
                    ),
                    onPressed: onToday,
                    child: const Text(
                      'Сегодня',
                      style: TextStyle(
                        fontSize: 12.16,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
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
}

class _TripsHeading extends StatelessWidget {
  const _TripsHeading({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ShiftColors.foreground)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              const Text(
                'Поездки',
                style: TextStyle(fontSize: 15.68, fontWeight: FontWeight.w600),
              ),
              Text(
                count.toString().padLeft(2, '0'),
                semanticsLabel: 'Поездок: $count',
                style: const TextStyle(
                  color: ShiftColors.muted,
                  fontSize: 11.2,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const Text(
            'СНАЧАЛА НОВЫЕ',
            style: TextStyle(
              color: ShiftColors.muted,
              fontSize: 8.64,
              letterSpacing: .8,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripLedgerRow extends StatelessWidget {
  const _TripLedgerRow({required this.trip, required this.last});

  final Trip trip;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final startDay = almatyDay(trip.start);
    final endDay = almatyDay(trip.end);
    return Container(
      key: ValueKey('trip-${trip.id}'),
      padding: const EdgeInsets.symmetric(vertical: 17),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: ShiftColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              MediaQuery.sizeOf(context).width <= 350 ||
              MediaQuery.textScalerOf(context).scale(16) >= 24 ||
              formatMoney(trip.amount).length > 18;
          final time = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${formatTripTime(trip.start)}–${formatTripTime(trip.end)}',
                style: const TextStyle(
                  fontSize: 16.64,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -.5,
                ),
              ),
              if (startDay != endDay) ...[
                const SizedBox(height: 4),
                Text(
                  'Конец: ${formatDay(endDay)}',
                  style: const TextStyle(
                    color: ShiftColors.muted,
                    fontSize: 12.16,
                  ),
                ),
              ],
            ],
          );
          final amount = Text(
            formatMoney(trip.amount),
            textAlign: stacked ? TextAlign.left : TextAlign.right,
            style: const TextStyle(
              fontSize: 20.8,
              fontWeight: FontWeight.w600,
              letterSpacing: -.94,
              height: 1.2,
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stacked) ...[
                time,
                const SizedBox(height: 8),
                amount,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: time),
                    const SizedBox(width: 12),
                    Expanded(child: amount),
                  ],
                ),
              const SizedBox(height: 9),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        trip.payment == PaymentMethod.card
                            ? Icons.credit_card_outlined
                            : Icons.payments_outlined,
                        size: 15,
                        color: ShiftColors.muted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        trip.payment == PaymentMethod.card
                            ? 'Карта'
                            : 'Наличные',
                        style: const TextStyle(
                          fontSize: 11.36,
                          color: ShiftColors.muted,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Комиссия ${formatMoney(trip.commission)}',
                    style: const TextStyle(
                      fontSize: 11.36,
                      height: 1.25,
                      color: ShiftColors.muted,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LoadingDay extends StatefulWidget {
  const _LoadingDay();

  @override
  State<_LoadingDay> createState() => _LoadingDayState();
}

class _LoadingDayState extends State<_LoadingDay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shimmer.stop();
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  Widget _block(double height, {double? width}) => Container(
    height: height,
    width: width,
    decoration: BoxDecoration(
      color: ShiftColors.soft,
      borderRadius: BorderRadius.circular(10),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _shimmer,
            builder: (context, child) => ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment(-3 + _shimmer.value * 6, 0),
                end: Alignment(-1 + _shimmer.value * 6, 0),
                colors: const [
                  ShiftColors.soft,
                  ShiftColors.surface,
                  ShiftColors.soft,
                ],
              ).createShader(bounds),
              child: child,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _block(225),
                const SizedBox(height: 10),
                _block(80),
                const SizedBox(height: 25),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _block(22, width: 120),
                ),
                const SizedBox(height: 16),
                _block(82),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: const Text(
            'Загружаем день…',
            style: TextStyle(color: ShiftColors.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _DayError extends StatelessWidget {
  const _DayError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 40,
            color: ShiftColors.error,
          ),
          const SizedBox(height: 16),
          const Text(
            'Не удалось загрузить день',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: ShiftColors.muted, height: 1.4),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            key: const Key('retry-day'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Поездок пока нет',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 8),
        Text(
          'Добавьте первую поездку за этот день.',
          style: TextStyle(
            color: ShiftColors.muted,
            fontSize: 14.4,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
