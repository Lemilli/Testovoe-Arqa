import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/trip_api.dart';
import '../formatting/diary_format.dart';
import '../models/day.dart';
import '../models/diary_date.dart';
import '../models/trip_input.dart';
import '../state/day_providers.dart';
import '../state/trip_submission.dart';

class TripForm extends ConsumerStatefulWidget {
  const TripForm({required this.initialDate, super.key});

  final DiaryDate initialDate;

  @override
  ConsumerState<TripForm> createState() => _TripFormState();
}

class _TripFormState extends ConsumerState<TripForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _commission;
  late DiaryDate _startDate;
  late DiaryDate _endDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late PaymentMethod _payment;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    final pending = ref.read(tripSubmissionProvider).pending;
    if (pending == null) {
      _startDate = _endDate = widget.initialDate;
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 9, minute: 30);
      _payment = PaymentMethod.cash;
    } else {
      _startDate = almatyDay(pending.start);
      _endDate = almatyDay(pending.end);
      _startTime = TimeOfDay.fromDateTime(almatyTime(pending.start));
      _endTime = TimeOfDay.fromDateTime(almatyTime(pending.end));
      _payment = pending.payment;
    }
    _amount = TextEditingController(text: pending?.amount.toString() ?? '');
    _commission = TextEditingController(
      text: pending?.commission.toString() ?? '0',
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _commission.dispose();
    super.dispose();
  }

  DateTime get _start =>
      almatyWallTime(_startDate, _startTime.hour, _startTime.minute);
  DateTime get _end => almatyWallTime(_endDate, _endTime.hour, _endTime.minute);

  String? _timeError() {
    try {
      if (!_end.isAfter(_start)) {
        return 'Окончание должно быть позже начала.';
      }
    } on FormatException catch (error) {
      return error.message;
    }
    return null;
  }

  Future<void> _chooseDate({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (start ? _startDate : _endDate).toDateTime,
      firstDate: DiaryDate.first.toDateTime,
      lastDate: start ? DiaryDate.last.toDateTime : DateTime.utc(9999, 12, 31),
      currentDate: ref.read(todayProvider).toDateTime,
      helpText: start ? 'Дата начала' : 'Дата окончания',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _startDate = DiaryDate.fromDateTime(picked);
      } else {
        _endDate = DiaryDate.fromDateTime(picked);
      }
    });
  }

  Future<void> _chooseTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
      helpText: start ? 'Время начала' : 'Время окончания',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _save() async {
    final state = ref.read(tripSubmissionProvider);
    if (state.isSending ||
        state.error?.outcome == TripFailureOutcome.conflict) {
      return;
    }
    final notifier = ref.read(tripSubmissionProvider.notifier);
    late final DiaryDate affectedDay;
    late final bool succeeded;
    if (state.isUncertain) {
      affectedDay = almatyDay(state.pending!.start);
      succeeded = await notifier.retry();
    } else {
      if (!_formKey.currentState!.validate()) return;
      late final TripInput input;
      try {
        input = TripInput(
          start: _start,
          end: _end,
          amount: TripInput.parseMoney(_amount.text),
          commission: TripInput.parseMoney(_commission.text),
          payment: _payment,
        );
      } on FormatException catch (error) {
        setState(() => _inputError = error.message);
        return;
      }
      setState(() => _inputError = null);
      affectedDay = almatyDay(input.start);
      FocusScope.of(context).unfocus();
      succeeded = await notifier.submit(input);
    }
    if (mounted && succeeded) Navigator.of(context).pop(affectedDay);
  }

  String _timeLabel(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  Widget _dateTimeFields({required bool start, required bool locked}) {
    final prefix = start ? 'start' : 'end';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          start ? 'Начало' : 'Окончание',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: Key('$prefix-date'),
          onPressed: locked ? null : () => _chooseDate(start: start),
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(
            formatDay(start ? _startDate : _endDate),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: Key('$prefix-time'),
          onPressed: locked ? null : () => _chooseTime(start: start),
          icon: const Icon(Icons.schedule),
          label: Text(_timeLabel(start ? _startTime : _endTime)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final submission = ref.watch(tripSubmissionProvider);
    final conflict = submission.error?.outcome == TripFailureOutcome.conflict;
    final locked = submission.isSending || submission.isUncertain || conflict;
    final theme = Theme.of(context);

    return PopScope(
      canPop: !submission.isSending,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Добавить поездку'),
          leading: IconButton(
            key: const Key('close-trip'),
            tooltip: 'Закрыть форму',
            onPressed: submission.isSending
                ? null
                : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                key: const Key('trip-form-scroll'),
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Время Алматы (Asia/Almaty)'),
                      const SizedBox(height: 16),
                      _dateTimeFields(start: true, locked: locked),
                      const SizedBox(height: 24),
                      _dateTimeFields(start: false, locked: locked),
                      FormField<void>(
                        validator: (_) => _timeError(),
                        builder: (field) => field.hasError
                            ? Padding(
                                key: const Key('trip-time-error'),
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  field.errorText!,
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        key: const Key('trip-amount'),
                        controller: _amount,
                        enabled: !locked,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Сумма, ₸',
                          helperText: 'Целые тенге, больше нуля',
                          border: OutlineInputBorder(),
                          errorMaxLines: 4,
                          helperMaxLines: 2,
                        ),
                        validator: (value) => TripInput.moneyError(
                          value ?? '',
                          isCommission: false,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('trip-commission'),
                        controller: _commission,
                        enabled: !locked,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Комиссия, ₸',
                          helperText: 'Сумма в целых тенге, от нуля',
                          border: OutlineInputBorder(),
                          errorMaxLines: 4,
                          helperMaxLines: 2,
                        ),
                        validator: (value) => TripInput.moneyError(
                          value ?? '',
                          isCommission: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<PaymentMethod>(
                        key: const Key('trip-payment'),
                        initialValue: _payment,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Способ оплаты',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: PaymentMethod.cash,
                            child: Text('Наличные', key: Key('payment-cash')),
                          ),
                          DropdownMenuItem(
                            value: PaymentMethod.card,
                            child: Text('Карта', key: Key('payment-card')),
                          ),
                        ],
                        onChanged: locked
                            ? null
                            : (value) => setState(() => _payment = value!),
                      ),
                      if (_inputError != null) ...[
                        const SizedBox(height: 24),
                        Text(
                          _inputError!,
                          key: const Key('trip-input-error'),
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      if (submission.error != null) ...[
                        const SizedBox(height: 24),
                        Text(
                          submission.error!.message,
                          key: const Key('trip-server-error'),
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      if (submission.isUncertain) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Пока неизвестно, сохранилась ли поездка. '
                          'Данные сохранены для повтора и временно недоступны '
                          'для изменения. Можно закрыть форму и вернуться '
                          'к отправке позже.',
                          key: Key('trip-retry-note'),
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (submission.isSending) ...[
                        const Center(child: CircularProgressIndicator()),
                        const SizedBox(height: 12),
                        const Text(
                          'Сохранение поездки…',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (conflict)
                        FilledButton(
                          key: const Key('reset-trip'),
                          onPressed: () {
                            ref.read(tripSubmissionProvider.notifier).reset();
                          },
                          child: const Text('Вернуться к форме'),
                        )
                      else
                        FilledButton(
                          key: Key(
                            submission.isUncertain ? 'retry-trip' : 'save-trip',
                          ),
                          onPressed: submission.isSending ? null : _save,
                          child: Text(
                            submission.isUncertain
                                ? 'Повторить отправку'
                                : 'Сохранить поездку',
                            textAlign: TextAlign.center,
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
    );
  }
}
