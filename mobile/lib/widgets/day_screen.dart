import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/day_api.dart';
import '../formatting/diary_format.dart';
import '../models/day.dart';
import '../models/diary_date.dart';
import '../state/day_providers.dart';
import 'trip_form.dart';

class DayScreen extends ConsumerWidget {
  const DayScreen({super.key});

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
              ? 'Поездка сохранена'
              : 'Поездка сохранена: ${formatDay(affectedDay)}',
        ),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref, DiaryDate date) async {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedDayProvider);
    final today = ref.watch(todayProvider);
    final day = ref.watch(dayProvider(selected));

    return Scaffold(
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton.icon(
            key: const Key('add-trip'),
            onPressed: () => _addTrip(context, ref, selected),
            icon: const Icon(Icons.add),
            label: const Text('Добавить поездку', textAlign: TextAlign.center),
          ),
        ),
      ),
      appBar: AppBar(
        title: const Text('Дневник смен'),
        actions: [
          IconButton(
            key: const Key('refresh-day'),
            tooltip: 'Обновить день',
            onPressed: day.isLoading ? null : () => _refresh(ref, selected),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 840,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            key: const Key('previous-day'),
                            tooltip: 'Предыдущий день',
                            onPressed: selected == DiaryDate.first
                                ? null
                                : ref
                                      .read(selectedDayProvider.notifier)
                                      .previous,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: TextButton.icon(
                              key: const Key('choose-day'),
                              onPressed: () =>
                                  _chooseDate(context, ref, selected),
                              icon: const Icon(Icons.calendar_month_outlined),
                              label: Text(
                                formatDay(selected),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const Key('next-day'),
                            tooltip: 'Следующий день',
                            onPressed: selected == DiaryDate.last
                                ? null
                                : ref.read(selectedDayProvider.notifier).next,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      if (selected != today)
                        TextButton(
                          key: const Key('today'),
                          onPressed: () => ref
                              .read(selectedDayProvider.notifier)
                              .select(today),
                          child: const Text('Сегодня'),
                        ),
                    ],
                  ),
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
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _LoadingDay(),
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
                              child: _DaySummary(summary: data.summary),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Поездки',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Время Алматы',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (data.trips.isEmpty)
                            const SliverPadding(
                              padding: EdgeInsets.fromLTRB(16, 12, 16, 32),
                              sliver: SliverToBoxAdapter(child: _EmptyDay()),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              sliver: SliverList.builder(
                                itemCount: data.trips.length,
                                itemBuilder: (context, index) =>
                                    _TripCard(trip: data.trips[index]),
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

class _LoadingDay extends StatelessWidget {
  const _LoadingDay();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Загрузка дня…'),
          ],
        ),
      ),
    );
  }
}

class _DayError extends StatelessWidget {
  const _DayError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('retry-day'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DaySummary extends StatelessWidget {
  const _DaySummary({required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryCard(
          label: 'На руки',
          value: formatMoney(summary.netIncome),
          highlighted: true,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final scaledText = MediaQuery.textScalerOf(context).scale(14);
            final columns = scaledText > 22 || constraints.maxWidth < 320
                ? 1
                : constraints.maxWidth >= 600
                ? 3
                : 2;
            final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
            final values = [
              (label: 'Поездок', value: summary.tripCount.toString()),
              (label: 'Выручка', value: formatMoney(summary.revenue)),
              (label: 'Комиссия', value: formatMoney(summary.commission)),
              (label: 'Наличные', value: formatMoney(summary.cash)),
              (label: 'Карта', value: formatMoney(summary.card)),
            ];
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in values)
                  SizedBox(
                    width: width,
                    child: _SummaryCard(label: entry.label, value: entry.value),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.filled(
      margin: EdgeInsets.zero,
      color: highlighted ? theme.colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: highlighted
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style:
                  (highlighted
                          ? theme.textTheme.headlineMedium
                          : theme.textTheme.titleLarge)
                      ?.copyWith(
                        color: highlighted
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      key: ValueKey('trip-${trip.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              formatTripRange(trip.start, trip.end),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      trip.payment == PaymentMethod.card
                          ? Icons.credit_card_outlined
                          : Icons.payments_outlined,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      trip.payment == PaymentMethod.card ? 'Карта' : 'Наличные',
                    ),
                  ],
                ),
                Text(
                  formatMoney(trip.amount),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Комиссия: ${formatMoney(trip.commission)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.directions_car_outlined,
          size: 40,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(
          'Поездок пока нет',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        const Text(
          'За выбранный день нет поездок.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
