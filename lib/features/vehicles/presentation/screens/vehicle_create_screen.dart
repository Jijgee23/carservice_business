import 'dart:async';

import 'package:carservice_business/app/shell/shell_chrome.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:carservice_business/core/utils/input_formatters.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/utils/validators.dart';
import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/features/customers/data/customer_repository.dart';
import 'package:carservice_business/features/customers/domain/customers_repository.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/features/orders/presentation/screens/new_customer_sheet.dart';
import 'package:carservice_business/features/vehicles/data/vehicle_lookup_repository.dart';
import 'package:carservice_business/features/vehicles/data/vehicle_repository.dart';
import 'package:carservice_business/features/vehicles/domain/vehicle.dart';
import 'package:carservice_business/features/vehicles/domain/vehicle_lookup.dart';
import 'package:carservice_business/features/vehicles/domain/vehicles_repository.dart';
import 'package:flutter/material.dart';
import 'package:carservice_business/core/widgets/plate/plate_field.dart';
import 'package:flutter/services.dart';

// Return type — vehicle + resolved customer
class NewVehicleResult {
  final VehicleSummary vehicle;
  final CustomerSummary? customer;
  const NewVehicleResult({required this.vehicle, required this.customer});
}

/// Standard Mongolian plate: 4 digits + 3 letters (Cyrillic or Latin). Same
/// pattern as the web form; it only decides whether the auto-lookup fires —
/// non-standard plates (transit etc.) can still be registered by hand.
final RegExp _kStandardPlate = RegExp(r'^\d{4}[А-ЯЁӨҮA-Z]{3}$');
const Duration _kLookupDebounce = Duration(milliseconds: 400);

/// Shared vehicle-create screen — `/vehicles/new` and the order-creation
/// fast path. Web parity: `app/dashboard/vehicles/create-vehicle-modal.tsx`.
/// The owner is REQUIRED (the server does not enforce it; this form does).
class VehicleCreateScreen extends StatefulWidget {
  /// Pre-fill plate if triggered from a search with no result
  final String? initialPlate;

  /// Pre-select the owner (order creation picks the customer first).
  final CustomerSummary? initialCustomer;

  /// Injectable for tests; default to the real remote adapters.
  final VehiclesRepository? vehiclesRepository;
  final CustomersRepository? customersRepository;
  final VehicleLookupRepository? lookupRepository;

  /// Injected by tests; production falls back to the signed-in user.
  final User? user;

  const VehicleCreateScreen({
    super.key,
    this.initialPlate,
    this.initialCustomer,
    this.vehiclesRepository,
    this.customersRepository,
    this.lookupRepository,
    this.user,
  });

  @override
  State<VehicleCreateScreen> createState() => _VehicleCreateScreenState();
}

class _VehicleCreateScreenState extends State<VehicleCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  late final VehiclesRepository _vehiclesRepo =
      widget.vehiclesRepository ?? RemoteVehiclesRepository();
  late final CustomersRepository _customersRepo =
      widget.customersRepository ?? RemoteCustomersRepository();
  late final VehicleLookupRepository _lookupRepo =
      widget.lookupRepository ?? RemoteVehicleLookupRepository();
  final _plateCtrl = TextEditingController();
  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _vinCtrl = TextEditingController();
  final _mileCtrl = TextEditingController();

  // Customer
  final _custCtrl = TextEditingController();
  List<CustomerSummary> _custResults = [];
  bool _searchingCust = false;
  CustomerSummary? _customer;
  Timer? _custTimer;

  // Plate lookup
  Timer? _lookupTimer;
  int _hurSeq = 0;
  bool _hurLoading = false;
  VehicleLookup? _lookup;
  String? _lookupError;
  bool _detailsExpanded = false;

  /// True while make/model/year/VIN controllers hold lookup-prefilled values,
  /// so a plate change can clear exactly those.
  bool _prefilled = false;

  // Owner registration from the plate (`POST customers/from-plate`)
  bool _registeringOwner = false;
  String? _registerError;

  /// "Дугааргүй" — plate sentinel is sent, lookup is hidden, VIN required.
  bool _noPlate = false;

  bool _saving = false;
  String? _generalError;
  Map<String, String> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    if (isNoPlate(widget.initialPlate)) {
      _noPlate = true;
    } else if (widget.initialPlate != null) {
      _plateCtrl.text = widget.initialPlate!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _schedulePlateLookup();
      });
    }
    _customer = widget.initialCustomer;
  }

  @override
  void dispose() {
    _plateCtrl.dispose();
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _yearCtrl.dispose();
    _vinCtrl.dispose();
    _mileCtrl.dispose();
    _custCtrl.dispose();
    _custTimer?.cancel();
    _lookupTimer?.cancel();
    super.dispose();
  }

  // ─── Derived state ─────────────────────────────────────────────────────────

  String get _plate => normalizePlate(_plateCtrl.text);
  bool get _isStandardPlate => _kStandardPlate.hasMatch(_plate);
  bool get _nonStandardPlate => _plate.isNotEmpty && !_isStandardPlate;
  bool get _hurComplete => _lookup?.isComplete ?? false;

  /// Web `showManual` rule: manual make/model/year/VIN only when the lookup
  /// gave nothing usable (error, partial result, non-standard plate) or in
  /// plate-less mode. When the lookup filled them they are read-only.
  bool get _showManual =>
      _noPlate ||
      (!_hurLoading &&
          _plate.isNotEmpty &&
          !_hurComplete &&
          (_lookupError != null || _nonStandardPlate || _lookup != null));

  bool get _canSubmit {
    if (_saving || _customer == null) return false;
    if (_noPlate) {
      return _makeCtrl.text.trim().isNotEmpty &&
          _modelCtrl.text.trim().isNotEmpty &&
          _vinCtrl.text.trim().isNotEmpty;
    }
    if (_plate.isEmpty) return false;
    return _hurComplete ||
        (_showManual &&
            _makeCtrl.text.trim().isNotEmpty &&
            _modelCtrl.text.trim().isNotEmpty);
  }

  // ─── Plate lookup ──────────────────────────────────────────────────────────

  /// Plate edited: drop the previous lookup (its make/VIN must never be saved
  /// under a different plate), cancel anything in flight, and re-arm the
  /// debounced auto-lookup for a standard plate.
  void _onPlateChanged(String _) {
    _lookupTimer?.cancel();
    _hurSeq++; // invalidate any in-flight lookup
    setState(() {
      _hurLoading = false;
      _lookup = null;
      _lookupError = null;
      _registerError = null;
      _detailsExpanded = false;
      if (_prefilled) {
        _makeCtrl.clear();
        _modelCtrl.clear();
        _yearCtrl.clear();
        _vinCtrl.clear();
        _prefilled = false;
      }
    });
    _schedulePlateLookup();
  }

  void _schedulePlateLookup() {
    _lookupTimer?.cancel();
    if (_noPlate || !_isStandardPlate) return;
    final plate = _plate;
    _lookupTimer = Timer(_kLookupDebounce, () {
      if (mounted) _lookupPlate(plate);
    });
  }

  /// Manual 🔍 — works for any non-empty plate, immediately.
  void _manualLookup() {
    _lookupTimer?.cancel();
    if (_plate.isEmpty) return;
    _lookupPlate(_plate);
  }

  /// A superseded call (newer lookup, plate edit, no-plate switch) returns
  /// without touching state: whoever bumped [_hurSeq] already reset
  /// [_hurLoading] or owns it, so the spinner can never stick.
  Future<void> _lookupPlate(String plate) async {
    final seq = ++_hurSeq;
    setState(() {
      _hurLoading = true;
      _lookup = null;
      _lookupError = null;
      _registerError = null;
    });
    final Result<VehicleLookup> res;
    try {
      res = await _lookupRepo.lookupVehicle(plate);
    } catch (_) {
      if (mounted && seq == _hurSeq) {
        setState(() {
          _hurLoading = false;
          _lookupError = 'Мэдээлэл татаж чадсангүй';
        });
      }
      return;
    }
    if (!mounted || seq != _hurSeq || _noPlate) return;
    switch (res) {
      case Ok(:final value):
        setState(() {
          _hurLoading = false;
          _lookup = value;
          _prefilled = true;
          _makeCtrl.text = value.make ?? '';
          _modelCtrl.text = value.model ?? '';
          _yearCtrl.text = value.year?.toString() ?? '';
          _vinCtrl.text = value.vin ?? '';
        });
        await _preselectMatchedCustomer(value.matchedCustomerId, seq);
      case Err(:final error):
        setState(() {
          _hurLoading = false;
          _lookupError = _lookupErrorText(error);
        });
    }
  }

  /// The owner's phone from the lookup is masked — never used. Only the
  /// server-matched tenant customer is preselected, and only if the user has
  /// not chosen one.
  Future<void> _preselectMatchedCustomer(String? id, int seq) async {
    if (id == null || _customer != null) return;
    final res = await _customersRepo.getCustomer(id);
    if (!mounted || seq != _hurSeq || _noPlate || _customer != null) return;
    if (res case Ok(:final value)) {
      final c = value.customer;
      setState(
        () => _customer = CustomerSummary(
          id: c.id,
          fullName: c.fullName,
          phone: c.phone ?? '',
          email: c.email,
        ),
      );
    }
  }

  String _lookupErrorText(AppError e) => switch (e.statusCode) {
    429 => 'Хэт олон хүсэлт илгээлээ. Түр хүлээгээд дахин оролдоно уу.',
    502 => 'ХУР-аас мэдээлэл татаж чадсангүй. Дараа дахин оролдоно уу.',
    404 => 'Улсын бүртгэлээс олдсонгүй',
    _ => e.display,
  };

  // ─── Owner from plate ──────────────────────────────────────────────────────

  Future<void> _registerOwner() async {
    if (_registeringOwner) return;
    final plate = _plate;
    final seq = _hurSeq;
    setState(() {
      _registeringOwner = true;
      _registerError = null;
    });
    Result<CustomerSummary>? res;
    try {
      res = await _lookupRepo.registerOwnerFromPlate(plate);
    } catch (_) {
      res = null;
    }
    if (!mounted) return;
    // Plate edited / mode switched while the POST was in flight: the owner
    // belongs to the old plate — drop the result, only release the flag.
    if (seq != _hurSeq || plate != _plate || _noPlate) {
      setState(() => _registeringOwner = false);
      return;
    }
    if (res == null) {
      setState(() {
        _registeringOwner = false;
        _registerError = 'Эзэмшигч бүртгэж чадсангүй';
      });
      return;
    }
    switch (res) {
      case Ok(:final value):
        setState(() {
          _registeringOwner = false;
          _customer = value;
          _custResults = [];
          _custCtrl.clear();
        });
      case Err(:final error):
        setState(() {
          _registeringOwner = false;
          _registerError = _registerErrorText(error);
        });
    }
  }

  String _registerErrorText(AppError e) {
    final fe = e.fieldErrors;
    if (fe != null && fe['plate'] != null) return fe['plate']!;
    if (e.statusCode == 404 && e.code == 'OWNER_NOT_FOUND') {
      return 'Эзэмшигчийн утасны мэдээлэл олдсонгүй.';
    }
    return switch (e.statusCode) {
      429 => 'Хэт олон хүсэлт илгээлээ. Түр хүлээгээд дахин оролдоно уу.',
      502 => 'ХУР-аас мэдээлэл татаж чадсангүй. Дараа дахин оролдоно уу.',
      _ => e.display,
    };
  }

  void _setNoPlate(bool v) {
    _lookupTimer?.cancel();
    setState(() {
      _noPlate = v;
      _hurSeq++; // drop any in-flight lookup
      _hurLoading = false;
      _lookup = null;
      _lookupError = null;
      _registerError = null;
      _detailsExpanded = false;
      if (_prefilled) {
        _makeCtrl.clear();
        _modelCtrl.clear();
        _yearCtrl.clear();
        _vinCtrl.clear();
        _prefilled = false;
      }
    });
    if (!v) _schedulePlateLookup();
  }

  // ─── Customer search ────────────────────────────────────────────────────────

  void _searchCustomer(String q) {
    _custTimer?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _custResults = [];
      });
      return;
    }
    _custTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _searchingCust = true);
      final result = await _customersRepo.getCustomers(
        query: CustomerListQuery(q: q.trim()),
      );
      if (!mounted) return;
      setState(() {
        _custResults = switch (result) {
          Ok(:final value) =>
            value.items
                .map(
                  (c) => CustomerSummary(
                    id: c.id,
                    fullName: c.fullName,
                    phone: c.phone ?? '',
                    email: c.email,
                    isOrganization: c.isOrganization,
                    orgName: c.orgName,
                    orgRegnum: c.orgRegnum,
                  ),
                )
                .toList(growable: false),
          Err() => const <CustomerSummary>[],
        };
        _searchingCust = false;
      });
    });
  }

  void _selectCustomer(CustomerSummary c) => setState(() {
    _customer = c;
    _custResults = [];
    _custCtrl.clear();
  });

  Future<void> _openNewCustomer() async {
    final result = await showNewCustomerSheet(context);
    if (result != null && mounted) _selectCustomer(result);
  }

  // ─── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_canSubmit) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _generalError = null;
      _fieldErrors = const {};
    });

    final lookup = _lookup;
    // Lookup filled make/model → send the lookup's own values and let the
    // server resolve the owner regnum (`fromLookup`). Otherwise manual values.
    final fromLookup = !_noPlate && lookup != null && lookup.isComplete;
    final plate = _noPlate ? kNoPlate : _plate;
    final make = fromLookup ? lookup.make!.trim() : _makeCtrl.text.trim();
    final model = fromLookup ? lookup.model!.trim() : _modelCtrl.text.trim();
    final year = fromLookup ? lookup.year : int.tryParse(_yearCtrl.text.trim());
    final vinRaw = fromLookup ? (lookup.vin ?? '') : _vinCtrl.text.trim();
    final vin = vinRaw.isEmpty ? null : vinRaw;
    final mileage = int.tryParse(_mileCtrl.text.trim());

    // NOTE: `POST /api/v1/vehicles` does not read `fuelType`/`wheelPosition`
    // (verified in app/api/v1/vehicles/route.ts), so they are not sent.
    Result<Vehicle> result;
    try {
      result = fromLookup
          ? await _lookupRepo.createVehicleFromLookup(
              plate: plate,
              make: make,
              model: model,
              year: year,
              vin: vin,
              mileage: mileage,
              customerId: _customer?.id,
            )
          : await _vehiclesRepo.createVehicle(
              plate: plate,
              make: make,
              model: model,
              year: year,
              vin: vin,
              mileage: mileage,
              customerId: _customer?.id,
            );
    } catch (_) {
      result = const Err(
        AppError(ErrorKind.unknown, 'Машин бүртгэж чадсангүй'),
      );
    }

    if (!mounted) return;

    switch (result) {
      case Ok(:final value):
        setState(() => _saving = false);
        // `POST /vehicles` returns the link's REAL owner, which may differ
        // from the requested `customerId` (`ensureTenantVehicle` never
        // overwrites an existing owner) — render what came back, never echo
        // the request. The response omits the nested `customer` block, so
        // the locally-known [_customer] is carried over only when the
        // returned id still matches what was sent.
        final withCustomer = VehicleSummary(
          id: value.id,
          plate: value.plate ?? plate,
          make: value.make ?? make,
          model: value.model ?? model,
          year: value.year,
          vin: value.vin,
          mileage: value.mileage,
          customerId: value.customerId ?? _customer?.id,
          customer:
              (value.customerId == null || value.customerId == _customer?.id)
              ? _customer
              : null,
        );

        AppNav.back(
          NewVehicleResult(vehicle: withCustomer, customer: _customer),
        );
      case Err(:final error):
        setState(() {
          _saving = false;
          _fieldErrors = error.fieldErrors ?? const {};
          _generalError = _generalErrorFor(error, fromLookup);
        });
    }
  }

  /// Field errors whose input is not rendered (make/model/year/vin on the
  /// fromLookup path, or any unknown key) would be invisible — surface them
  /// in the general banner instead.
  String? _generalErrorFor(AppError error, bool fromLookup) {
    final fe = error.fieldErrors;
    if (fe == null || fe.isEmpty) return error.display;
    final visible = <String>{
      if (!_noPlate) 'plate',
      'mileage',
      'customerId',
      if (!fromLookup) ...['make', 'model', 'year', 'vin'],
    };
    final hidden = fe.entries
        .where((e) => !visible.contains(e.key))
        .map((e) => e.value)
        .toList();
    return hidden.isEmpty ? null : hidden.join(' ');
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  Widget _plateField(BuildContext context) {
    final helper = _hurLoading
        ? 'ХУР-аас татаж байна...'
        : _nonStandardPlate
        ? 'Стандарт бус дугаар — улсын бүртгэлээс шалгахгүй, мэдээллийг гараар оруулна.'
        : (_isStandardPlate ? null : 'Жишээ: 1234УБА');
    return _LabelField(
      label: 'Улсын дугаар *',
      // Digits then Cyrillic letters from its own keypad; kept canonical.
      child: PlateField(
        fieldKey: const Key('vehicleCreate.plate'),
        controller: _plateCtrl,
        onChanged: _onPlateChanged,
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Улсын дугаар оруулна уу' : null,
        style: context.textStyles.body,
        decoration: InputDecoration(
          hintText: '1234ҮНА',
          helperText: helper,
          helperMaxLines: 2,
          errorText: _fieldErrors['plate'],
          suffixIcon: _hurLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    key: Key('vehicleCreate.lookupSpinner'),
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: Icon(
                    _lookup != null ? Icons.check_circle : Icons.search,
                    color: _lookup != null
                        ? context.opsGood
                        : context.opsAccent,
                    size: 20,
                  ),
                  tooltip: 'ХУР-аас хайх',
                  onPressed: _manualLookup,
                ),
        ),
      ),
    );
  }

  Widget _manualFields(BuildContext context) {
    final String note = _noPlate
        ? 'Марк, загвар, арлын дугаар (VIN) заавал — дугааргүй машиныг VIN-ээр ялгана.'
        : _lookup != null
        ? 'Улсын бүртгэлээс ирсэн мэдээлэл дутуу байна — гараар нөхнө үү.'
        : _lookupError != null
        ? 'Улсын бүртгэлээс олдсонгүй — мэдээллийг гараар оруулна уу.'
        : 'Мэдээллийг гараар оруулна уу.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Divider(),
        Text(note, style: context.textStyles.caption),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _LabelField(
                label: 'Марк *',
                child: TextFormField(
                  key: const Key('vehicleCreate.make'),
                  controller: _makeCtrl,
                  onChanged: (_) => setState(() {}),
                  textCapitalization: TextCapitalization.words,
                  validator: requiredFieldLabel('Марк'),
                  style: context.textStyles.body,
                  decoration: InputDecoration(
                    hintText: 'Toyota',
                    errorText: _fieldErrors['make'],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _LabelField(
                label: 'Загвар *',
                child: TextFormField(
                  key: const Key('vehicleCreate.model'),
                  controller: _modelCtrl,
                  onChanged: (_) => setState(() {}),
                  textCapitalization: TextCapitalization.words,
                  validator: requiredFieldLabel('Загвар'),
                  style: context.textStyles.body,
                  decoration: InputDecoration(
                    hintText: 'Prius',
                    errorText: _fieldErrors['model'],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _LabelField(
          label: 'Үйлдвэрлэгдсэн он',
          child: TextFormField(
            key: const Key('vehicleCreate.year'),
            controller: _yearCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: context.textStyles.body,
            decoration: InputDecoration(
              hintText: '2020',
              counterText: '',
              errorText: _fieldErrors['year'],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _LabelField(
          label: _noPlate ? 'VIN дугаар *' : 'VIN дугаар',
          child: TextFormField(
            key: const Key('vehicleCreate.vin'),
            controller: _vinCtrl,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
              const UpperCaseTextFormatter(),
            ],
            validator: AppValidators.vin(required: _noPlate),
            style: context.textStyles.body,
            decoration: InputDecoration(
              hintText: 'JTDKN3DU...',
              errorText: _fieldErrors['vin'],
            ),
          ),
        ),
      ],
    );
  }

  /// Required-field validator for the manual fields.
  String? Function(String?) requiredFieldLabel(String label) =>
      (v) => (v == null || v.trim().isEmpty) ? '$label оруулна уу' : null;

  @override
  Widget build(BuildContext context) {
    final lookup = _lookup;
    return Scaffold(
      backgroundColor: context.opsBackground,
      appBar: AppBar(
        title: Text('Шинэ машин бүртгэх'),
        actions: const [ShellNotificationBell()],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_generalError != null) ...[
                      _InfoBanner(
                        icon: Icons.error_outline,
                        color: context.opsDanger,
                        text: _generalError!,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Машины мэдээлэл ──────────────────────────────────
                    _SectionHeader(
                      icon: Icons.directions_car_outlined,
                      title: 'Машины мэдээлэл',
                    ),
                    const SizedBox(height: 12),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_noPlate)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Улсын дугааргүй машин',
                                    style: context.textStyles.bodyMedium,
                                  ),
                                ),
                                TextButton(
                                  key: const Key('vehicleCreate.backToPlate'),
                                  onPressed: _saving
                                      ? null
                                      : () => _setNoPlate(false),
                                  child: const Text('← Улсын дугаартай'),
                                ),
                              ],
                            )
                          else ...[
                            _plateField(context),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                key: const Key('vehicleCreate.noPlate'),
                                onPressed: _saving
                                    ? null
                                    : () => _setNoPlate(true),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  '+ Улсын дугааргүй машин бүртгэх',
                                ),
                              ),
                            ),
                          ],

                          if (!_noPlate && _lookupError != null) ...[
                            const SizedBox(height: 8),
                            _InfoBanner(
                              key: const Key('vehicleCreate.lookupError'),
                              icon: Icons.error_outline,
                              color: context.opsDanger,
                              text: _lookupError!,
                            ),
                          ],

                          if (!_noPlate &&
                              lookup != null &&
                              lookup.registered) ...[
                            const SizedBox(height: 8),
                            _InfoBanner(
                              key: const Key('vehicleCreate.registered'),
                              icon: Icons.info_outline,
                              color: context.opsWarning,
                              text:
                                  'Танай бүртгэлд ижил дугаартай машин байна. '
                                  'Өөр эзэн бол шинээр бүртгэж болно — түүх өмнөх эзэнд үлдэнэ.',
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                key: const Key('vehicleCreate.viewRegistered'),
                                onPressed: () => AppNav.push('/vehicles'),
                                child: const Text('Бүртгэлээс харах →'),
                              ),
                            ),
                          ],

                          if (!_noPlate && lookup != null) ...[
                            const SizedBox(height: 8),
                            _LookupInfoBox(
                              lookup: lookup,
                              expanded: _detailsExpanded,
                              onToggle: () => setState(
                                () => _detailsExpanded = !_detailsExpanded,
                              ),
                              ownerAction: _ownerAction(context, lookup),
                            ),
                          ],

                          if (_showManual) _manualFields(context),

                          const _Divider(),

                          // Mileage (app feature, optional)
                          _LabelField(
                            label: 'Гүйлт (км)',
                            child: TextFormField(
                              key: const Key('vehicleCreate.mileage'),
                              controller: _mileCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(
                                  kMileageMaxDigits,
                                ),
                              ],
                              style: context.textStyles.body,
                              decoration: InputDecoration(
                                hintText: '85000',
                                errorText: _fieldErrors['mileage'],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Эзэмшигч ─────────────────────────────────────────
                    _SectionHeader(
                      icon: Icons.person_outline,
                      title: 'Эзэмшигч *',
                      trailing: _customer == null
                          ? TextButton.icon(
                              onPressed: _openNewCustomer,
                              icon: const Icon(Icons.add, size: 16),
                              label: Text('Шинэ'),
                              style: TextButton.styleFrom(
                                foregroundColor: context.opsAccent,
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            )
                          : null,
                    ),
                    if (_fieldErrors['customerId'] != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _fieldErrors['customerId']!,
                          style: TextStyle(
                            color: context.opsDanger,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    if (_customer == null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Эзэмшигч сонгоогүй байна — машин бүртгэхийн тулд эзэмшигч заавал сонгоно.',
                        key: const Key('vehicleCreate.ownerRequired'),
                        style: context.textStyles.caption,
                      ),
                    ],
                    const SizedBox(height: 12),

                    if (_customer != null) ...[
                      _SelectedCustomerCard(
                        customer: _customer!,
                        onClear: () => setState(() => _customer = null),
                      ),
                    ] else ...[
                      _Card(
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _custCtrl,
                              onChanged: _searchCustomer,
                              style: context.textStyles.body,
                              decoration: InputDecoration(
                                hintText: 'Нэр, утас, регистрээр хайх...',
                                prefixIcon: Icon(
                                  Icons.search,
                                  size: 18,
                                  color: context.opsTextHint,
                                ),
                                suffixIcon: _searchingCust
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : null,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                            if (_custResults.isNotEmpty) ...[
                              const Divider(height: 1),
                              ..._custResults
                                  .take(4)
                                  .map(
                                    (c) => InkWell(
                                      onTap: () => _selectCustomer(c),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.person_outline,
                                              size: 16,
                                              color: context.opsTextSecondary,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    c.displayName,
                                                    style: context
                                                        .textStyles
                                                        .bodyMedium,
                                                  ),
                                                  Text(
                                                    [
                                                      ?c.orgRegnumLabel,
                                                      c.phone,
                                                    ].join(' · '),
                                                    style: context
                                                        .textStyles
                                                        .caption,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                              Icons.add,
                                              size: 16,
                                              color: context.opsAccent,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                            ],
                            if (_custResults.isEmpty &&
                                _custCtrl.text.isEmpty) ...[
                              Divider(height: 1),
                              InkWell(
                                onTap: _openNewCustomer,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.person_add_outlined,
                                        size: 16,
                                        color: context.opsAccent,
                                      ),
                                      SizedBox(width: 10),
                                      Text(
                                        'Шинэ үйлчлүүлэгч бүртгэх',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: context.opsAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // Sticky submit
            Container(
              decoration: BoxDecoration(
                color: context.opsSurface,
                border: Border(top: BorderSide(color: context.opsDivider)),
              ),
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                12 + MediaQuery.of(context).padding.bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  key: const Key('vehicleCreate.submit'),
                  onPressed: _canSubmit ? _save : null,
                  child: _saving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.opsTextOnDark,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 18,
                              color: context.opsTextOnDark,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Машин бүртгэх',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: context.opsTextOnDark,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "→ Эзэмшигчээр бүртгэх" (+ inline error) shown inside the owner row of
  /// the info box. Hidden once an owner is chosen, when the lookup has no
  /// owner phone, or without `customers.create`.
  Widget? _ownerAction(BuildContext context, VehicleLookup lookup) {
    final owner = lookup.owner;
    if (owner == null || !owner.hasPhone || _customer != null) return null;
    return PermissionGate(
      permission: 'customers.create',
      user: widget.user,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton(
            key: const Key('vehicleCreate.registerOwner'),
            onPressed: _registeringOwner ? null : _registerOwner,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
            ),
            child: Text(
              _registeringOwner ? 'Бүртгэж байна...' : '→ Эзэмшигчээр бүртгэх',
            ),
          ),
          if (_registerError != null)
            Text(
              _registerError!,
              key: const Key('vehicleCreate.registerError'),
              style: TextStyle(color: context.opsDanger, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

/// Lookup result box — web `create-vehicle-modal.tsx` info panel.
class _LookupInfoBox extends StatelessWidget {
  const _LookupInfoBox({
    required this.lookup,
    required this.expanded,
    required this.onToggle,
    this.ownerAction,
  });

  final VehicleLookup lookup;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget? ownerAction;

  Widget _row(BuildContext context, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: context.textStyles.caption),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: context.textStyles.body,
            ),
          ),
        ],
      ),
    );
  }

  static String? _wheel(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return null;
    final l = v.toLowerCase();
    if (l.startsWith('зүүн') || l == 'left' || l == 'l') return 'Зүүн';
    if (l.startsWith('баруун') || l == 'right' || l == 'r') return 'Баруун';
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final owner = lookup.owner;
    return Container(
      key: const Key('vehicleCreate.infoBox'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.opsBackground,
        borderRadius: BorderRadius.circular(AppDimens.radiusSM),
        border: Border.all(color: context.opsDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lookup.isGlobal
                ? 'Системийн бүртгэлээс'
                : 'HUR-аас татсан мэдээлэл',
            style: context.textStyles.caption.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          _row(context, 'Марк', lookup.make),
          _row(context, 'Модель', lookup.model),
          _row(context, 'VIN', lookup.vin),
          _row(context, 'Үйлдвэрлэгдсэн он', lookup.year?.toString()),
          _row(context, 'Импортлогдсон', lookup.importDate),
          if (expanded) ...[
            _row(context, 'Өнгө', lookup.color),
            _row(
              context,
              'Багтаамж',
              lookup.capacity != null ? '${lookup.capacity} см³' : null,
            ),
            _row(context, 'Түлшний төрөл', lookup.fuelType),
            _row(context, 'Ангилал', lookup.className),
            _row(context, 'Зориулалт', lookup.purpose),
            _row(context, 'Үйлдвэрлэгдсэн улс', lookup.country),
            _row(context, 'Жолоо', _wheel(lookup.wheelPosition)),
          ],
          TextButton(
            key: const Key('vehicleCreate.toggleDetails'),
            onPressed: onToggle,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
            ),
            child: Text(expanded ? '← Хураангуй' : 'Дэлгэрэнгүй →'),
          ),
          if (owner != null) ...[
            const Divider(height: 12),
            Text(
              'Эзэмшигч (HUR): ${owner.displayName}'
              '${owner.kind != null ? ' · ${owner.kind}' : ''}'
              '${owner.hasPhone ? ' · ${owner.phone}' : ''}',
              key: const Key('vehicleCreate.ownerInfo'),
              style: context.textStyles.body,
            ),
            ?ownerAction,
          ],
        ],
      ),
    );
  }
}
// ─── Local helpers ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: context.opsPrimary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(AppDimens.radiusSM),
          ),
          child: Icon(icon, size: 16, color: context.opsPrimary),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: context.textStyles.h3)),
        ?trailing,
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(color: context.opsDivider),
        boxShadow: [
          BoxShadow(
            color: context.opsTextPrimary.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }
}

class _LabelField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabelField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.opsTextSecondary,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 10),
    child: Divider(height: 1),
  );
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoBanner({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppDimens.radiusSM),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedCustomerCard extends StatelessWidget {
  final CustomerSummary customer;
  final VoidCallback onClear;
  const _SelectedCustomerCard({required this.customer, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(color: context.opsGood.withOpacity(0.4), width: 1.5),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: context.opsGood.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                customer.displayName.isNotEmpty
                    ? customer.displayName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: context.opsGood,
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.displayName,
                  style: context.textStyles.bodyMedium,
                ),
                Text(customer.phone, style: context.textStyles.caption),
                if (customer.email != null && customer.email!.isNotEmpty)
                  Text(
                    customer.email!,
                    style: context.textStyles.caption.copyWith(
                      color: context.opsTextHint,
                    ),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: context.opsBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                size: 14,
                color: context.opsTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
