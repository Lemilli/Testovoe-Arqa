import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/trip_api.dart';
import '../formatting/diary_format.dart';
import '../models/day.dart';
import '../models/diary_date.dart';
import '../models/trip_input.dart';
import '../state/day_providers.dart';
import '../state/trip_submission.dart';
import '../theme/shift_theme.dart';

class TripForm extends ConsumerStatefulWidget {
  const TripForm({required this.initialDate, super.key});

  final DiaryDate initialDate;

  @override
  ConsumerState<TripForm> createState() => _TripFormState();
}

class _TripFormState extends ConsumerState<TripForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountAnchor = GlobalKey();
  final _commissionAnchor = GlobalKey();
  final _startTimeAnchor = GlobalKey();
  final _endTimeAnchor = GlobalKey();
  final _statusAnchor = GlobalKey();
  final _amountFocus = FocusNode();
  final _commissionFocus = FocusNode();
  final _startDateFocus = FocusNode();
  final _startTimeFocus = FocusNode();
  final _endDateFocus = FocusNode();
  final _endTimeFocus = FocusNode();
  late final TextEditingController _amount;
  late final TextEditingController _commission;
  late DiaryDate _startDate;
  late DiaryDate _endDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late PaymentMethod _payment;
  String? _inputError;

  static const _labelStyle = TextStyle(
    color: ShiftColors.muted,
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w500,
  );
  static const _noteStyle = TextStyle(fontSize: 13.76, height: 1.36);
  static const _errorStyle = TextStyle(
    color: ShiftColors.error,
    fontSize: 12,
    height: 1.25,
  );

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
    for (final node in [
      _amountFocus,
      _commissionFocus,
      _startDateFocus,
      _startTimeFocus,
      _endDateFocus,
      _endTimeFocus,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  DateTime get _start =>
      almatyWallTime(_startDate, _startTime.hour, _startTime.minute);
  DateTime get _end => almatyWallTime(_endDate, _endTime.hour, _endTime.minute);

  String? _timeError() {
    try {
      final start = _start;
      final end = _end;
      if (!end.isAfter(start)) {
        return 'Окончание должно быть позже начала.';
      }
    } on FormatException catch (error) {
      return error.message;
    }
    return null;
  }

  void _reveal(GlobalKey anchor, {FocusNode? focus}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      focus?.requestFocus();
      final target = anchor.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _revealFirstError() {
    if (TripInput.moneyError(_amount.text, isCommission: false) != null) {
      _reveal(_amountAnchor, focus: _amountFocus);
      return;
    }
    if (TripInput.moneyError(_commission.text, isCommission: true) != null) {
      _reveal(_commissionAnchor, focus: _commissionFocus);
      return;
    }
    try {
      almatyWallTime(_startDate, _startTime.hour, _startTime.minute);
    } on FormatException {
      _reveal(_startTimeAnchor, focus: _startTimeFocus);
      return;
    }
    _reveal(_endTimeAnchor, focus: _endTimeFocus);
  }

  Future<void> _chooseDate({required bool start}) async {
    FocusScope.of(context).unfocus();
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
      _inputError = null;
    });
  }

  Future<void> _chooseTime({required bool start}) async {
    FocusScope.of(context).unfocus();
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
      _inputError = null;
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
      if (!_formKey.currentState!.validate()) {
        _revealFirstError();
        return;
      }
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
        _revealFirstError();
        return;
      }
      setState(() => _inputError = null);
      affectedDay = almatyDay(input.start);
      FocusScope.of(context).unfocus();
      succeeded = await notifier.submit(input);
    }
    if (mounted && succeeded) Navigator.of(context).pop(affectedDay);
  }

  String _timeLabel(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _dateLabel(DiaryDate date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString().padLeft(4, '0');
    return '$day.$month.$year';
  }

  Widget _sectionHeading(String number, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        ExcludeSemantics(
          child: Text(
            number,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 9.8,
              color: ShiftColors.muted,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13.92,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  InputDecoration _moneyDecoration({String? hint}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: ShiftColors.muted),
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: ShiftColors.accent, width: 2),
    ),
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: ShiftColors.error, width: 2),
    ),
    filled: false,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(vertical: 6),
    constraints: const BoxConstraints(minHeight: 48),
    errorMaxLines: 5,
    errorStyle: _errorStyle,
  );

  Widget _moneyFields({required bool locked, required bool largeText}) {
    final commissionField = Semantics(
      label: 'Комиссия, ₸',
      child: TextFormField(
        key: const Key('trip-commission'),
        controller: _commission,
        focusNode: _commissionFocus,
        enabled: !locked,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        textAlign: largeText ? TextAlign.left : TextAlign.right,
        style: const TextStyle(
          color: ShiftColors.foreground,
          fontSize: 17.92,
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
        decoration: _moneyDecoration(),
        validator: (value) =>
            TripInput.moneyError(value ?? '', isCommission: true),
        onChanged: (_) => setState(() => _inputError = null),
      ),
    );
    final commissionLabel = ExcludeSemantics(
      child: Text('Комиссия, ₸', style: _labelStyle),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeading('01', 'Расчёт'),
        Container(
          key: _amountAnchor,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          decoration: BoxDecoration(
            color: ShiftColors.surface,
            border: Border.all(color: ShiftColors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Text('Сумма поездки, ₸', style: _labelStyle),
              ),
              const SizedBox(height: 5),
              Semantics(
                label: 'Сумма поездки, ₸',
                child: TextFormField(
                  key: const Key('trip-amount'),
                  controller: _amount,
                  focusNode: _amountFocus,
                  enabled: !locked,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _commissionFocus.requestFocus(),
                  style: TextStyle(
                    color: ShiftColors.foreground,
                    fontSize: largeText ? 28.8 : 45.6,
                    height: 1.2,
                    letterSpacing: largeText ? -1.2 : -2.7,
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: _moneyDecoration(hint: '0'),
                  validator: (value) =>
                      TripInput.moneyError(value ?? '', isCommission: false),
                  onChanged: (_) => setState(() => _inputError = null),
                ),
              ),
            ],
          ),
        ),
        Padding(
          key: _commissionAnchor,
          padding: const EdgeInsets.only(top: 14),
          child: largeText
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [commissionLabel, commissionField],
                )
              : Row(
                  children: [
                    Expanded(child: commissionLabel),
                    const SizedBox(width: 16),
                    Expanded(child: commissionField),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _paymentChoice(PaymentMethod value, {required bool locked}) {
    final selected = _payment == value;
    final key = value == PaymentMethod.cash ? 'payment-cash' : 'payment-card';
    final label = value == PaymentMethod.cash ? 'Наличные' : 'Карта';
    return OutlinedButton(
      key: Key(key),
      onPressed: locked ? null : () => setState(() => _payment = value),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 56),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        shape: const RoundedRectangleBorder(),
        side: BorderSide.none,
        backgroundColor: selected ? ShiftColors.foreground : Colors.transparent,
        disabledBackgroundColor: selected
            ? ShiftColors.foreground
            : Colors.transparent,
        foregroundColor: selected
            ? ShiftColors.surface
            : ShiftColors.foreground,
        disabledForegroundColor: selected
            ? ShiftColors.surface
            : ShiftColors.foreground,
        textStyle: const TextStyle(
          fontSize: 14.4,
          fontWeight: FontWeight.w600,
          height: 1.15,
        ),
      ),
      child: Semantics(
        selected: selected,
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            Icon(
              value == PaymentMethod.cash
                  ? Icons.payments_outlined
                  : Icons.credit_card,
              size: 19,
            ),
            Text(label),
          ],
        ),
      ),
    );
  }

  Widget _paymentFields({required bool locked}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionHeading('02', 'Оплата'),
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: ShiftColors.foreground),
            borderRadius: BorderRadius.circular(16),
          ),
          child: IntrinsicHeight(
            child: Row(
              key: const Key('trip-payment'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _paymentChoice(PaymentMethod.cash, locked: locked),
                ),
                Expanded(
                  child: _paymentChoice(PaymentMethod.card, locked: locked),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  Widget _dateTimeControl({
    required bool start,
    required bool date,
    required bool locked,
  }) {
    final prefix = start ? 'start' : 'end';
    final kind = date ? 'date' : 'time';
    final selectedDate = start ? _startDate : _endDate;
    final fullDate = formatDay(selectedDate);
    final value = date
        ? _dateLabel(selectedDate)
        : _timeLabel(start ? _startTime : _endTime);
    final focus = start
        ? (date ? _startDateFocus : _startTimeFocus)
        : (date ? _endDateFocus : _endTimeFocus);
    final dateDescription = start ? 'Дата начала' : 'Дата окончания';
    final timeDescription = start ? 'Время начала' : 'Время окончания';
    final visibleLabel = date
        ? (start ? 'Начало · дата' : 'Конец · дата')
        : 'Время';
    return OutlinedButton(
      key: Key('$prefix-$kind'),
      focusNode: focus,
      onPressed: locked
          ? null
          : () => date ? _chooseDate(start: start) : _chooseTime(start: start),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 80),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide.none,
        foregroundColor: ShiftColors.foreground,
        disabledForegroundColor: ShiftColors.foreground,
      ),
      child: Semantics(
        label: date
            ? '$dateDescription: $fullDate'
            : '$timeDescription: $value',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(visibleLabel, style: _labelStyle),
              const SizedBox(height: 10),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15.04,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateTimeFields({
    required bool start,
    required bool locked,
    required bool stacked,
  }) {
    final date = _dateTimeControl(start: start, date: true, locked: locked);
    final time = Container(
      key: start ? _startTimeAnchor : _endTimeAnchor,
      child: _dateTimeControl(start: start, date: false, locked: locked),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: ShiftColors.border)),
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [date, time],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 11, child: date),
                const SizedBox(width: 16),
                Expanded(flex: 9, child: time),
              ],
            ),
    );
  }

  Widget _statusNote(TripSubmissionState state, {required bool conflict}) {
    final sending = state.isSending;
    final error = state.error != null;
    final title = sending
        ? 'Отправляем поездку'
        : state.isUncertain
        ? 'Результат отправки неизвестен'
        : 'Не удалось сохранить';
    return Semantics(
      liveRegion: true,
      child: Container(
        key: _statusAnchor,
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: error ? ShiftColors.errorBackground : ShiftColors.surface,
          border: Border.all(
            color: error ? ShiftColors.error : ShiftColors.border,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              sending ? Icons.sync : Icons.warning_amber_rounded,
              size: 20,
              color: error ? ShiftColors.error : ShiftColors.accent,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: _noteStyle.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  if (sending)
                    const Text(
                      'Поля и переходы временно недоступны.',
                      style: _noteStyle,
                    ),
                  if (state.error != null)
                    Text(
                      state.error!.message,
                      key: const Key('trip-server-error'),
                      style: _noteStyle,
                    ),
                  if (state.isUncertain) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Данные сохранены без изменений. Повторная отправка '
                      'использует те же значения. Можно вернуться к дню '
                      'и продолжить позже.',
                      key: Key('trip-retry-note'),
                      style: _noteStyle,
                    ),
                  ],
                  if (conflict) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Вернитесь к редактированию, чтобы проверить поля '
                      'перед новой отправкой.',
                      style: _noteStyle,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(TripSubmissionState state, {required bool conflict}) {
    final label = state.isSending
        ? 'Отправляем…'
        : conflict
        ? 'Вернуться к редактированию'
        : state.isUncertain
        ? 'Повторить отправку'
        : 'Сохранить поездку';
    final key = conflict
        ? 'reset-trip'
        : state.isUncertain
        ? 'retry-trip'
        : 'save-trip';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Align(
          heightFactor: 1,
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: FilledButton(
                key: Key(key),
                onPressed: state.isSending
                    ? null
                    : conflict
                    ? () {
                        ref.read(tripSubmissionProvider.notifier).reset();
                        _reveal(_amountAnchor, focus: _amountFocus);
                      }
                    : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  backgroundColor: ShiftColors.accent,
                  foregroundColor: ShiftColors.surface,
                  disabledBackgroundColor: ShiftColors.border,
                  disabledForegroundColor: ShiftColors.muted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15.04,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                child: Row(
                  children: [
                    if (state.isSending) ...[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: Text(label)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final submission = ref.watch(tripSubmissionProvider);
    final conflict = submission.error?.outcome == TripFailureOutcome.conflict;
    final locked = submission.isSending || submission.isUncertain || conflict;
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;
    ref.listen(tripSubmissionProvider, (previous, next) {
      if ((next.isSending && !(previous?.isSending ?? false)) ||
          (next.error != null && next.error != previous?.error)) {
        _reveal(_statusAnchor);
      }
    });

    return PopScope(
      canPop: !submission.isSending,
      child: Scaffold(
        backgroundColor: ShiftColors.background,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: ShiftColors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          toolbarHeight: largeText ? 104 : 76,
          titleSpacing: 16,
          title: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 608),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('close-trip'),
                    tooltip: 'Вернуться к дню',
                    onPressed: submission.isSending
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      fixedSize: const Size(48, 48),
                      side: const BorderSide(color: ShiftColors.border),
                      shape: const CircleBorder(),
                      foregroundColor: ShiftColors.foreground,
                      disabledForegroundColor: ShiftColors.muted,
                    ),
                    icon: const Icon(Icons.arrow_back, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: const Text(
                        'Новая поездка',
                        style: TextStyle(
                          color: ShiftColors.foreground,
                          fontSize: 17.92,
                          fontWeight: FontWeight.w600,
                          height: 1.14,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 640,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth <= 350 || largeText;
                  return SingleChildScrollView(
                    key: const Key('trip-form-scroll'),
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (submission.isSending || submission.error != null)
                            _statusNote(submission, conflict: conflict),
                          _moneyFields(locked: locked, largeText: largeText),
                          const SizedBox(height: 24),
                          _paymentFields(locked: locked),
                          const SizedBox(height: 24),
                          _sectionHeading('03', 'Время поездки'),
                          _dateTimeFields(
                            start: true,
                            locked: locked,
                            stacked: stacked,
                          ),
                          _dateTimeFields(
                            start: false,
                            locked: locked,
                            stacked: stacked,
                          ),
                          FormField<void>(
                            validator: (_) => _timeError(),
                            builder: (field) => field.hasError
                                ? Padding(
                                    key: const Key('trip-time-error'),
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      field.errorText!,
                                      style: _errorStyle,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const Text(
                            'Время Алматы',
                            style: TextStyle(
                              color: ShiftColors.muted,
                              fontSize: 11.68,
                              height: 1.3,
                            ),
                          ),
                          if (_inputError != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _inputError!,
                              key: const Key('trip-input-error'),
                              style: const TextStyle(color: ShiftColors.error),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        bottomNavigationBar: _footer(submission, conflict: conflict),
      ),
    );
  }
}
