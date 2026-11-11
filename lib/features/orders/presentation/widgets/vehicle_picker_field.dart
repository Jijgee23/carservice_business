import 'dart:async';

import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/plate_registration.dart';
import 'package:carservice_business/core/services/diagnostic_service.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/utils/validators.dart';
import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';

typedef VehicleSearch = Future<List<VehicleSummary>> Function(String query);

typedef PlateRegister = Future<Result<PlateRegistration>> Function({
  required String plate,
  String? customerId,
  String? make,
  String? model,
});

/// The order form's «Машин» picker, working like the web order form's
/// vehicle select (`carservice.mn/app/dashboard/orders/order-form.tsx`):
///
/// - a searchable dropdown (plate, make, owner), clearable;
/// - with a [customer] it lists only their vehicles ([customerVehicles]);
///   without one it searches the tenant's vehicles that have an owner —
///   picking one makes its owner the customer (the parent's job);
/// - a standard plate that isn't listed offers «+ 1234УБА — машин бүртгэх»:
///   the server fetches the vehicle by plate and registers it for the
///   customer, or ownerless (then linked to the customer the order is
///   created for). Nothing found → asks for make and model inline;
/// - ownerless vehicles registered here stay listed for the session.
class VehiclePickerField extends StatefulWidget {
  const VehiclePickerField({
    super.key,
    required this.value,
    required this.customer,
    required this.customerVehicles,
    required this.onChanged,
    this.loadingCustomerVehicles = false,
    this.canRegister = true,
    this.errorText,
    this.search,
    this.register,
    this.onRegisterManually,
  });

  final VehicleSummary? value;
  final CustomerSummary? customer;

  /// The [customer]'s vehicles (loaded by the parent); unused without one.
  final List<VehicleSummary> customerVehicles;
  final bool loadingCustomerVehicles;

  /// Null = cleared. A registered vehicle comes back with [customer]
  /// attached when it was registered for them.
  final ValueChanged<VehicleSummary?> onChanged;

  /// False hides the «+ бүртгэх» row. The web shows it to everyone and lets
  /// the server refuse (no `vehicles.create` → the error under the field).
  final bool canRegister;
  final String? errorText;

  /// Defaults to [DiagnosticService.searchVehicles].
  final VehicleSearch? search;

  /// Defaults to [DiagnosticService.registerVehicleFromPlate].
  final PlateRegister? register;

  /// Full vehicle form for what the plate row can't do (no plate, transit
  /// plates, VIN only…). Null hides the sheet's footer link.
  final VoidCallback? onRegisterManually;

  @override
  State<VehiclePickerField> createState() => _VehiclePickerFieldState();
}

class _VehiclePickerFieldState extends State<VehiclePickerField> {
  /// Ownerless vehicles registered here — listed even with no customer.
  final List<VehicleSummary> _registered = [];
  bool _registering = false;
  String? _registerError;

  /// Nothing found by plate: the inline make/model form.
  ({String plate, String reason})? _details;
  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();

  @override
  void dispose() {
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _change(VehicleSummary? v) {
    setState(() => _registerError = null);
    widget.onChanged(v);
  }

  Future<void> _open() async {
    final outcome = await showModalBottomSheet<_SheetOutcome>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      backgroundColor: CarserviceTheme.of(context).panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _VehiclePickerSheet(
        selected: widget.value,
        customer: widget.customer,
        customerVehicles: widget.customerVehicles,
        registered: List.unmodifiable(_registered),
        canRegister: widget.canRegister,
        search: widget.search ?? DiagnosticService.searchVehicles,
        onRegisterManually: widget.onRegisterManually,
      ),
    );
    if (!mounted || outcome == null) return;
    switch (outcome) {
      case _Picked(:final vehicle):
        _change(vehicle);
      case _Create(:final plate):
        await _registerPlate(plate);
      case _Manual():
        widget.onRegisterManually?.call();
    }
  }

  Future<void> _registerPlate(String plate, {String? make, String? model}) async {
    final customer = widget.customer;
    setState(() {
      _registering = true;
      _registerError = null;
    });
    final register = widget.register ?? DiagnosticService.registerVehicleFromPlate;
    final res = await register(plate: plate, customerId: customer?.id, make: make, model: model);
    if (!mounted) return;
    setState(() => _registering = false);
    switch (res) {
      case Err(:final error):
        setState(() => _registerError = error.fieldErrors?.values.firstOrNull ?? error.display);
      case Ok(value: PlateNeedsDetails(:final reason)):
        setState(() => _details = (plate: plate, reason: reason));
      case Ok(value: PlateRegistered(:final vehicle)):
        final v = customer != null && vehicle.customerId == customer.id
            ? _withCustomer(vehicle, customer)
            : vehicle;
        setState(() {
          if (v.customerId == null) {
            _registered
              ..removeWhere((x) => x.id == v.id)
              ..insert(0, v);
          }
          _details = null;
          _makeCtrl.clear();
          _modelCtrl.clear();
        });
        _change(v);
    }
  }

  /// The hint under the field — same cases as the web form.
  String? get _fieldHint {
    final v = widget.value;
    if (_registering) return 'Машин бүртгэж байна…';
    if (v != null && v.customerId == null) {
      return 'Эзэмшигчгүй — сонгосон үйлчлүүлэгчид холбогдоно';
    }
    if (v != null && _isOrg(v)) return 'Эзэмшигч: байгууллага';
    if (widget.customer == null) return 'Сонгоход эзэмшигч автоматаар бичигдэнэ';
    if (!widget.loadingCustomerVehicles && widget.customerVehicles.isEmpty && _registered.isEmpty) {
      return 'Машин бүртгэгдээгүй — дугаараа бичиж бүртгэнэ';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final v = widget.value;
    final enabled = !_registering;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('vehicle_picker_field'),
          onTap: enabled ? _open : null,
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: InputDecorator(
            isEmpty: v == null,
            decoration: InputDecoration(
              enabled: enabled,
              hintText: '— Сонгох —',
              helperText: _fieldHint,
              helperMaxLines: 2,
              errorText: _registerError ?? widget.errorText,
              errorMaxLines: 3,
              prefixIcon: const Icon(Icons.directions_car_outlined, size: 20),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (v != null && enabled)
                    IconButton(
                      key: const ValueKey('vehicle_picker_clear'),
                      tooltip: 'Машиныг цэвэрлэх',
                      onPressed: () => _change(null),
                      icon: Icon(Icons.close_rounded, size: 18, color: t.mutedText),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _registering
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
                          )
                        : Icon(Icons.expand_more_rounded, color: t.mutedText),
                  ),
                ],
              ),
            ),
            child: v == null
                ? null
                : Column(
                    key: const ValueKey('vehicle_picker_selected'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Wraps rather than cuts: the plate must read in full.
                      Text(
                        plateLabel(v.plate, v.vin),
                        style: opsMono(
                          context,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: t.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _summaryLine(v, widget.customer),
                        style: TextStyle(fontSize: 13, color: t.mutedText),
                      ),
                    ],
                  ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: _details == null ? const SizedBox(width: double.infinity) : _detailsForm(t),
        ),
      ],
    );
  }

  Widget _detailsForm(CarserviceTheme t) {
    final details = _details!;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        key: const ValueKey('vehicle_picker_details'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.panel2,
          borderRadius: BorderRadius.circular(AppRadii.panel),
          border: Border.all(color: t.border),
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge([_makeCtrl, _modelCtrl]),
          builder: (context, _) {
            final ready = _makeCtrl.text.trim().isNotEmpty && _modelCtrl.text.trim().isNotEmpty;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: details.plate,
                        style: opsMono(
                          context,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: t.ink,
                        ),
                      ),
                      TextSpan(text: ' · ${details.reason}'),
                    ],
                  ),
                  style: TextStyle(fontSize: 12, color: t.mutedText3),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('vehicle_picker_make'),
                        controller: _makeCtrl,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Марк',
                          hintText: 'Toyota',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('vehicle_picker_model'),
                        controller: _modelCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Загвар',
                          hintText: 'Prius',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _registering
                          ? null
                          : () => setState(() {
                              _details = null;
                              _makeCtrl.clear();
                              _modelCtrl.clear();
                            }),
                      child: const Text('Болих'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('vehicle_picker_register_details'),
                      onPressed: _registering || !ready
                          ? null
                          : () => _registerPlate(
                              details.plate,
                              make: _makeCtrl.text.trim(),
                              model: _modelCtrl.text.trim(),
                            ),
                      style: FilledButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: t.onAccent,
                      ),
                      child: Text(_registering ? '…' : 'Бүртгэх'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── The dropdown ─────────────────────────────────────────────────────────────

sealed class _SheetOutcome {
  const _SheetOutcome();
}

final class _Picked extends _SheetOutcome {
  const _Picked(this.vehicle);
  final VehicleSummary vehicle;
}

final class _Create extends _SheetOutcome {
  const _Create(this.plate);
  final String plate;
}

final class _Manual extends _SheetOutcome {
  const _Manual();
}

class _VehiclePickerSheet extends StatefulWidget {
  const _VehiclePickerSheet({
    required this.selected,
    required this.customer,
    required this.customerVehicles,
    required this.registered,
    required this.canRegister,
    required this.search,
    required this.onRegisterManually,
  });

  final VehicleSummary? selected;
  final CustomerSummary? customer;
  final List<VehicleSummary> customerVehicles;
  final List<VehicleSummary> registered;
  final bool canRegister;
  final VehicleSearch search;
  final VoidCallback? onRegisterManually;

  @override
  State<_VehiclePickerSheet> createState() => _VehiclePickerSheetState();
}

class _VehiclePickerSheetState extends State<_VehiclePickerSheet> {
  /// Long lists show the first rows and ask for a narrower search (web).
  static const _maxVisible = 100;

  final _queryCtrl = TextEditingController();
  Timer? _debounce;
  int _seq = 0;

  /// Server results and the query they answer (no customer only).
  List<VehicleSummary> _results = const [];
  String? _resultsQuery;
  bool _loading = false;

  bool get _serverMode => widget.customer == null;
  String get _query => _queryCtrl.text.trim();

  @override
  void initState() {
    super.initState();
    // Like the web dropdown, open with options listed.
    if (_serverMode) _runSearch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onQuery(String _) {
    setState(() {});
    if (!_serverMode) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(_query));
  }

  Future<void> _runSearch(String query) async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final results = await widget.search(query);
    if (!mounted || seq != _seq) return;
    setState(() {
      _results = results;
      _resultsQuery = query;
      _loading = false;
    });
  }

  bool _matches(VehicleSummary v, String query) =>
      _matchesQuery('${plateLabel(v.plate, v.vin)} ${_optionHint(v, widget.customer)}', query);

  /// The listed vehicles: the customer's (filtered here), or the server's
  /// owned results; plus the ownerless ones registered this session.
  List<VehicleSummary> get _options {
    final q = _query;
    final registeredIds = {for (final v in widget.registered) v.id};
    final local = widget.registered.where((v) => q.isEmpty || _matches(v, q));
    final Iterable<VehicleSummary> rest = _serverMode
        ? _results.where((v) => v.customerId != null || registeredIds.contains(v.id))
        : widget.customerVehicles.where((v) => q.isEmpty || _matches(v, q));
    final seen = <String>{};
    return [
      for (final v in [...local, ...rest])
        if (seen.add(v.id)) v,
    ];
  }

  /// «+ 1234УБА — машин бүртгэх» for a standard plate that isn't listed.
  ({String plate, String label, String hint})? _createRow(List<VehicleSummary> options) {
    if (!widget.canRegister || _query.isEmpty) return null;
    final plate = normalizePlate(_query);
    if (!_standardPlate.hasMatch(plate)) return null;
    // Wait for this query's results: don't offer a plate the search may list.
    if (_serverMode && (_loading || _resultsQuery != _query)) return null;
    if (options.any((v) => comparablePlate(v.plate) == plate)) return null;
    final owner = widget.customer;
    return (
      plate: plate,
      label: '+ $plate — машин бүртгэх',
      hint: owner != null
          ? 'Мэдээллийг дугаараар татаж ${owner.displayName}-д бүртгэнэ'
          : 'Мэдээллийг дугаараар татаж бүртгэнэ (үйлчлүүлэгчийг дараа нь сонгоно)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final media = MediaQuery.of(context);
    final options = _options;
    final visible = options.take(_maxVisible).toList();
    final hidden = options.length - visible.length;
    final create = _createRow(options);
    final waiting = _serverMode && (_loading || _resultsQuery != _query);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: BorderRadius.circular(AppDimens.radiusFull),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.customer == null
                          ? 'Машин сонгох'
                          : '${widget.customer!.displayName} — машин',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: t.ink),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Хаах',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: t.mutedText),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                key: const ValueKey('vehicle_picker_search'),
                controller: _queryCtrl,
                autofocus: true,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                onChanged: _onQuery,
                onSubmitted: (_) {
                  // Enter on a lone row picks it, as on the web.
                  if (create != null && visible.isEmpty) {
                    Navigator.of(context).pop(_Create(create.plate));
                  } else if (visible.length == 1 && create == null) {
                    Navigator.of(context).pop(_Picked(visible.single));
                  }
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Дугаар, марк, эзэмшигчээр хайх…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _loading
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
                          ),
                        )
                      : null,
                ),
              ),
            ),
            Divider(height: 1, color: t.border),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (final v in visible)
                    _OptionRow(
                      key: ValueKey('vehicle_picker_option_${v.id}'),
                      label: plateLabel(v.plate, v.vin),
                      hint: _optionHint(v, widget.customer),
                      selected: v.id == widget.selected?.id,
                      onTap: () => Navigator.of(context).pop(_Picked(v)),
                    ),
                  if (create != null)
                    _OptionRow(
                      key: const ValueKey('vehicle_picker_create'),
                      label: create.label,
                      hint: create.hint,
                      accent: true,
                      onTap: () => Navigator.of(context).pop(_Create(create.plate)),
                    ),
                  if (visible.isEmpty && create == null && !waiting)
                    _Note(
                      widget.customer != null &&
                              widget.customerVehicles.isEmpty &&
                              widget.registered.isEmpty &&
                              _query.isEmpty
                          ? 'Машин бүртгэгдээгүй — дугаараа бичиж бүртгэнэ'
                          : 'Олдсонгүй',
                    ),
                  if (hidden > 0) _Note('+$hidden бичлэг — нарийвчлан бичиж хайна уу'),
                ],
              ),
            ),
            if (widget.onRegisterManually != null) ...[
              Divider(height: 1, color: t.border),
              SafeArea(
                top: false,
                child: TextButton.icon(
                  key: const ValueKey('vehicle_picker_manual'),
                  onPressed: () => Navigator.of(context).pop(const _Manual()),
                  style: TextButton.styleFrom(
                    foregroundColor: t.mutedText,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.edit_note_rounded, size: 20),
                  label: const Text('Дугааргүй / бусад машин бүртгэх'),
                ),
              ),
            ] else
              SizedBox(height: media.padding.bottom),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.label,
    required this.hint,
    required this.onTap,
    this.selected = false,
    this.accent = false,
  });

  final String label;
  final String hint;
  final VoidCallback onTap;
  final bool selected;

  /// The «+ бүртгэх» row.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final labelColor = accent || selected ? t.accent : t.ink;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? t.accent.withValues(alpha: 0.06) : null,
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: accent
                        ? TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: labelColor)
                        : opsMono(
                            context,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: labelColor,
                          ),
                  ),
                  if (hint.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(hint, style: TextStyle(fontSize: 12.5, color: t.mutedText)),
                  ],
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_rounded, size: 18, color: t.accent),
            ],
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, color: CarserviceTheme.of(context).mutedText3),
    ),
  );
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

/// 4 digits + 3 letters, after [normalizePlate] (web `isStandardPlate`):
/// only these are looked up by plate.
final _standardPlate = RegExp(r'^\d{4}[А-ЯЁӨҮA-Z]{3}$');

bool _isOrg(VehicleSummary v) => v.ownerIsOrganization || (v.customer?.isOrganization ?? false);

/// Make + model, the owner when no customer is picked, the organisation
/// note — what the field shows under the picked plate.
String _summaryLine(VehicleSummary v, CustomerSummary? customer) {
  final owner = v.customer;
  final makeModel = '${v.make} ${v.model}'.trim();
  final base = customer == null && owner != null ? '$makeModel · ${owner.displayName}' : makeModel;
  return _isOrg(v) ? '$base · Байгууллага' : base;
}

/// The grey line under a vehicle in the dropdown — web option `hint`: the
/// summary plus the ownerless / postpaid notes (the field's hint says those
/// once a vehicle is picked).
String _optionHint(VehicleSummary v, CustomerSummary? customer) {
  final line = _summaryLine(v, customer);
  if (v.customerId == null) return '$line · Эзэмшигчгүй — сонгосон үйлчлүүлэгчид холбогдоно';
  if (v.isPostpaid) return '$line · Дараа төлбөрт';
  return line;
}

VehicleSummary _withCustomer(VehicleSummary v, CustomerSummary customer) => VehicleSummary(
  id: v.id,
  plate: v.plate,
  vin: v.vin,
  make: v.make,
  model: v.model,
  year: v.year,
  mileage: v.mileage,
  customerId: v.customerId,
  customer: customer,
  isPostpaid: v.isPostpaid,
  ownerIsOrganization: v.ownerIsOrganization || customer.isOrganization,
);

// Web `foldSearch` / `matchesSelectQuery`: every word must appear in the
// label or hint, ignoring case, spaces and dashes, Latin typed for Cyrillic
// and the easily mistyped ө/ү/э/ё/й.
const _latinToCyrillic = {
  'a': 'а', 'b': 'б', 'c': 'ц', 'd': 'д', 'e': 'е', 'f': 'ф', 'g': 'г', //
  'h': 'х', 'i': 'и', 'j': 'ж', 'k': 'к', 'l': 'л', 'm': 'м', 'n': 'н', //
  'o': 'о', 'p': 'п', 'q': 'к', 'r': 'р', 's': 'с', 't': 'т', 'u': 'у', //
  'v': 'в', 'w': 'в', 'x': 'х', 'y': 'у', 'z': 'з',
};
const _cyrillicFold = {'ө': 'о', 'ү': 'у', 'э': 'е', 'ё': 'е', 'й': 'и'};
final _foldStrip = RegExp(r'[\s\-_.()+]');

String _fold(String text) {
  final buf = StringBuffer();
  for (final ch in text.toLowerCase().replaceAll(_foldStrip, '').split('')) {
    buf.write(_cyrillicFold[_latinToCyrillic[ch] ?? ch] ?? _latinToCyrillic[ch] ?? ch);
  }
  return buf.toString();
}

bool _matchesQuery(String haystack, String query) {
  final tokens = query.split(RegExp(r'\s+')).map(_fold).where((t) => t.isNotEmpty);
  if (tokens.isEmpty) return true;
  final folded = _fold(haystack);
  return tokens.every(folded.contains);
}
