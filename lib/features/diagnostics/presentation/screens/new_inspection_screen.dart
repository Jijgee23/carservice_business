import 'package:carservice_business/features/shell/presentation/controllers/working_branch_controller.dart';
import 'package:carservice_business/app/shell/shell_chrome.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/domain/models.dart';
import 'package:carservice_business/features/controllers.dart';
import 'package:carservice_business/core/services/diagnostic_service.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/core/widgets/plate/plate_field.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/create_template_screen.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/report_detail_screen.dart';
import 'package:carservice_business/core/utils/upload_image.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/utils/validators.dart';
import 'package:carservice_business/core/utils/input_formatters.dart';
import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:carservice_business/features/customers/data/customer_repository.dart';
import 'package:carservice_business/features/customers/domain/customers_repository.dart';
import 'package:carservice_business/features/vehicles/data/vehicle_repository.dart';
import 'package:carservice_business/features/vehicles/domain/vehicles_repository.dart';

// ─── АЛХАМ 0: Template сонгох ─────────────────────────────────────────────────

// NewInspectionScreen өөрөө NewInspectionController provide хийдэг.
// Ингэснээр screen pop болоход controller автоматаар dispose хийгдэнэ.
class NewInspectionScreen extends StatelessWidget {
  const NewInspectionScreen({super.key});

  /// Called from order detail: pre-fills provider and jumps straight to checklist.
  static Future<void> pushFromOrder(
    BuildContext context, {
    required String orderId,
    required String itemId,
    required VehicleSummary vehicle,
    required CustomerSummary customer,
    required String templateId,
  }) async {
    if (!canSeeView(Authenticator.user, 'diagnostics.create')) {
      messageError('Оношилгооны тайлан үүсгэх эрх хүрэлцэхгүй байна.');
      return;
    }
    final provider = NewInspectionController();
    try {
      provider.setOrderId(orderId);
      provider.setItemId(itemId);
      provider.setVehicle(vehicle, customer: customer);
      await provider.selectTemplate(templateId);
      if (!context.mounted || provider.template == null) return;
      await AppNav.to<void>(
        ChangeNotifierProvider.value(
          value: provider,
          child: const _ChecklistStep(),
        ),
        name: _orderFormRouteName,
      );
    } finally {
      provider.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NewInspectionController(),
      child: const _NewInspectionBody(),
    );
  }
}

class _NewInspectionBody extends StatefulWidget {
  const _NewInspectionBody();

  @override
  State<_NewInspectionBody> createState() => _NewInspectionBodyState();
}

class _NewInspectionBodyState extends State<_NewInspectionBody> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NewInspectionController>().loadTemplates();
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<NewInspectionController>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Оношилгооны загвар'),
        leading: BackButton(onPressed: () => AppNav.back()),
        actions: const [ShellNotificationBell()],
      ),
      floatingActionButton: PermissionGate(
        permission: 'diagnostics.create',
        child: FloatingActionButton.extended(
          onPressed: () async {
            final result = await AppNav.to<dynamic>(
              const CreateTemplateScreen(),
            );
            if (result != null && context.mounted) {
              context.read<NewInspectionController>().loadTemplates();
            }
          },
          backgroundColor: context.colors.accent,
          foregroundColor: CarserviceTheme.of(context).onAccent,
          icon: const Icon(Icons.add_rounded),
          label: Text(
            'Загвар үүсгэх',
            style: context.textStyles.body.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      body: PermissionGate(
        permission: 'diagnostics.create',
        fallback: const Center(
          child: Text('Оношилгооны тайлан үүсгэх эрх хүрэлцэхгүй байна.'),
        ),
        child: prov.loadingTemplates
            ? const AppLoading()
            : prov.templates.isEmpty
            ? const EmptyState(
                message: 'Оношилгооны загвар олдсонгүй.\nВеб дашбоардаас загвар үүсгэнэ үү.',
                icon: Icons.description_outlined,
              )
            : ListView(
                padding: const EdgeInsets.all(AppDimens.paddingMD),
                children: [
                  Text('Загвар сонгоно уу', style: context.textStyles.h3),
                  const SizedBox(height: 4),
                  Text(
                    'Тайлан бөглөхийн өмнө загвараа сонгоно уу.',
                    style: context.textStyles.caption,
                  ),
                  const SizedBox(height: 16),
                  ...prov.templates.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TemplateCard(
                        template: t,
                        onTap: () => _onSelectTemplate(context, t.id),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _onSelectTemplate(BuildContext context, String id) async {
    final prov = context.read<NewInspectionController>();
    prov.reset();
    await prov.selectTemplate(id);
    if (!context.mounted) return;
    if (prov.template == null) return;
    AppNav.to(
      ChangeNotifierProvider.value(value: prov, child: const _VehicleStep()),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final DiagnosticTemplateSummary template;
  final VoidCallback onTap;
  const _TemplateCard({required this.template, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.colors.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppDimens.radiusMD),
            ),
            child: Icon(
              Icons.description_outlined,
              color: context.colors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(template.name, style: context.textStyles.bodyMedium),
                const SizedBox(height: 2),
                Text(template.type.label, style: context.textStyles.caption),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: context.colors.textHint),
        ],
      ),
    );
  }
}

// ─── АЛХАМ 1: Машин / Үйлчлүүлэгч ───────────────────────────────────────────

class _VehicleStep extends StatefulWidget {
  const _VehicleStep();

  @override
  State<_VehicleStep> createState() => _VehicleStepState();
}

class _VehicleStepState extends State<_VehicleStep> {
  // Shared repositories: typed errors keep server `fieldErrors` (VIN, name...)
  // so they render inline instead of the legacy helper's global toast.
  final VehiclesRepository _vehiclesRepo = RemoteVehiclesRepository();
  final CustomersRepository _customersRepo = RemoteCustomersRepository();
  Map<String, String> _vehicleErrors = const {};
  Map<String, String> _customerErrors = const {};
  String? _createError;

  final _plateCtrl = TextEditingController();
  List<VehicleSummary> _results = [];
  bool _searching = false;
  bool _showCreateForm = false;

  // HUR lookup state
  bool _hurLoading = false;
  bool _hurFound = false;
  int _hurSeq = 0;

  /// "Дугааргүй" — plate sentinel is sent, HUR lookup is hidden, VIN required.
  bool _noPlate = false;

  // Create form controllers
  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _vinCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _mileageCtrl = TextEditingController();

  // Customer search
  final _custSearchCtrl = TextEditingController();
  List<CustomerSummary> _customerResults = [];
  bool _searchingCustomers = false;
  CustomerSummary? _selectedCustomer;
  Timer? _custSearchTimer;

  // Customer create form
  final _custNameCtrl = TextEditingController();
  final _custPhoneCtrl = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _custSearchTimer?.cancel();
    _plateCtrl.dispose();
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _vinCtrl.dispose();
    _yearCtrl.dispose();
    _mileageCtrl.dispose();
    _custSearchCtrl.dispose();
    _custNameCtrl.dispose();
    _custPhoneCtrl.dispose();
    super.dispose();
  }

  /// True when a search result must be dropped. A superseded search leaves
  /// the flags to the newer one; a no-plate switch with the same seq clears
  /// them here so the spinner can never stick.
  bool _abortSearch(int seq) {
    if (!mounted) return true;
    if (seq != _hurSeq) return true;
    if (_noPlate) {
      setState(() {
        _searching = false;
        _hurLoading = false;
      });
      return true;
    }
    return false;
  }

  Future<void> _search() async {
    final q = normalizePlate(_plateCtrl.text);
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _showCreateForm = false;
      _hurFound = false;
      _results = [];
    });
    final seq = ++_hurSeq;
    _results = await DiagnosticService.searchVehicles(q);
    if (_abortSearch(seq)) return;
    if (_results.isEmpty) {
      setState(() => _hurLoading = true);
      final lookup = await DiagnosticService.lookupHurWithMatch(q);
      if (_abortSearch(seq)) return;
      final hurData = lookup?.vehicle;
      // Owner phone is masked server-side; use only the tenant-scoped match,
      // and only when the user has not already chosen a customer.
      final matchedId = lookup?.matchedCustomerId;
      if (matchedId != null && _selectedCustomer == null) {
        final res = await _customersRepo.getCustomer(matchedId);
        if (_abortSearch(seq)) return;
        if (res case Ok(:final value)
            when mounted && _selectedCustomer == null) {
          final c = value.customer;
          _selectedCustomer = CustomerSummary(
            id: c.id,
            fullName: c.fullName,
            phone: c.phone ?? '',
            email: c.email,
          );
        }
      }
      if (mounted) {
        setState(() {
          _hurLoading = false;
          if (hurData != null) {
            _hurFound = true;
            _makeCtrl.text = (hurData['make'] ?? hurData['brand'] ?? '')
                .toString();
            _modelCtrl.text = (hurData['model'] ?? hurData['modelName'] ?? '')
                .toString();
            _yearCtrl.text = (hurData['year'] ?? hurData['buildYear'] ?? '')
                .toString();
            _vinCtrl.text = (hurData['vin'] ?? hurData['vinNumber'] ?? '')
                .toString();
          }
        });
      }
    }
    if (mounted) {
      setState(() {
        _searching = false;
        if (_results.isEmpty) _showCreateForm = true;
      });
    }
  }

  void _searchCustomers(String q) {
    _custSearchTimer?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _customerResults = []);
      return;
    }
    _custSearchTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() => _searchingCustomers = true);
      final results = await DiagnosticService.searchCustomers(q.trim());
      if (!mounted) return;
      setState(() {
        _customerResults = results;
        _searchingCustomers = false;
      });
    });
  }

  void _selectVehicle(VehicleSummary v) {
    final prov = context.read<NewInspectionController>();
    prov.setVehicle(v, customer: v.customer);
    _pushChecklist();
  }

  Future<void> _create() async {
    final plate = _noPlate ? kNoPlate : normalizePlate(_plateCtrl.text);
    final make = _makeCtrl.text.trim();
    final model = _modelCtrl.text.trim();

    if (plate.isEmpty || make.isEmpty || model.isEmpty) return;

    final vin = _vinCtrl.text.trim();
    final vinError = AppValidators.vin(required: _noPlate)(vin);
    if (vinError != null) {
      setState(() => _vehicleErrors = {'vin': vinError});
      return;
    }

    setState(() {
      _creating = true;
      _createError = null;
      _vehicleErrors = const {};
      _customerErrors = const {};
    });
    try {
      CustomerSummary? customer = _selectedCustomer;
      if (customer == null) {
        final custName = _custNameCtrl.text.trim();
        final custPhone = _custPhoneCtrl.text.trim();
        if (custName.isEmpty || custPhone.isEmpty) return;
        final res = await _customersRepo.createCustomer(
          fullName: custName,
          phone: custPhone,
        );
        if (!mounted) return;
        switch (res) {
          case Ok(:final value):
            final c = value.customer;
            customer = CustomerSummary(
              id: c.id,
              fullName: c.fullName,
              phone: c.phone ?? custPhone,
              email: c.email,
            );
            // Remember the created customer so a vehicle-create failure +
            // retry does not create it a second time.
            _selectedCustomer = customer;
          case Err(:final error):
            setState(() {
              _customerErrors = error.fieldErrors ?? const {};
              _createError = _customerErrors.isEmpty ? error.display : null;
            });
            return;
        }
      }

      final year = int.tryParse(_yearCtrl.text.trim());
      final mileage = int.tryParse(_mileageCtrl.text.trim());
      final res = await _vehiclesRepo.createVehicle(
        plate: plate,
        make: make,
        model: model,
        vin: vin.isEmpty ? null : vin,
        year: year,
        mileage: mileage,
        customerId: customer.id,
      );
      if (!mounted) return;
      switch (res) {
        case Ok(:final value):
          final vehicle = VehicleSummary(
            id: value.id,
            plate: value.plate ?? plate,
            vin: value.vin,
            make: value.make ?? make,
            model: value.model ?? model,
            year: value.year,
            mileage: value.mileage,
            customerId: value.customerId ?? customer.id,
            customer: customer,
          );
          context.read<NewInspectionController>().setVehicle(
            vehicle,
            customer: customer,
          );
          _pushChecklist();
        case Err(:final error):
          setState(() {
            _vehicleErrors = error.fieldErrors ?? const {};
            _createError = _vehicleErrors.isEmpty ? error.display : null;
          });
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _pushChecklist() {
    final prov = context.read<NewInspectionController>();
    AppNav.to(
      ChangeNotifierProvider.value(value: prov, child: const _ChecklistStep()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<NewInspectionController>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Машин хайх'),
        leading: BackButton(onPressed: () => AppNav.back()),
        actions: const [ShellNotificationBell()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimens.paddingMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (prov.template != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: context.colors.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppDimens.radiusSM),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 16,
                      color: context.colors.accent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      prov.template!.name,
                      style: context.textStyles.captionMedium.copyWith(
                        color: context.colors.accent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Улсын дугаар', style: context.textStyles.h3),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Дугааргүй',
                              style: context.textStyles.bodyMedium,
                            ),
                            Text(
                              'Улсын дугаар аваагүй машин — VIN заавал',
                              style: context.textStyles.caption,
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: _noPlate,
                        onChanged: _creating
                            ? null
                            : (v) => setState(() {
                                _noPlate = v;
                                // Drop any in-flight search / HUR lookup.
                                _hurSeq++;
                                _hurLoading = false;
                                _hurFound = false;
                                _searching = false;
                                _results = [];
                                _showCreateForm = v;
                              }),
                      ),
                    ],
                  ),
                  if (!_noPlate) ...[
                    const SizedBox(height: 12),
                    Text('Дугаар', style: context.textStyles.captionMedium),
                    const SizedBox(height: 6),
                    // Digits then Cyrillic letters from the field's keypad;
                    // «Бэлэн» searches.
                    PlateField(
                      fieldKey: const ValueKey('inspection_plate'),
                      controller: _plateCtrl,
                      onChanged: (_) {
                        setState(() {
                          _results = [];
                          _showCreateForm = false;
                        });
                      },
                      onSubmitted: (_) {
                        if (!_searching) _search();
                      },
                      decoration: InputDecoration(
                        hintText: '1234УБА',
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                key: const ValueKey('inspection_plate_search'),
                                tooltip: 'Хайх',
                                icon: const Icon(Icons.search),
                                onPressed: _search,
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // HUR loading indicator
            if (_hurLoading) ...[
              const SizedBox(height: 12),
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('ХУР бүртгэлд хайж байна...'),
                ],
              ),
            ],

            if (_results.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Олдсон машин(ууд)',
                style: context.textStyles.captionMedium,
              ),
              const SizedBox(height: 8),
              ..._results.map(
                (v) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    onTap: () => _selectVehicle(v),
                    child: Row(
                      children: [
                        Icon(
                          Icons.directions_car_outlined,
                          color: context.colors.accent,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                plateLabel(v.plate, v.vin),
                                style: context.textStyles.bodyMedium,
                              ),
                              Text(
                                v.displayName,
                                style: context.textStyles.caption,
                              ),
                              if (v.customer != null)
                                Text(
                                  v.customer!.displayName,
                                  style: context.textStyles.caption,
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: context.colors.textHint,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            if (_showCreateForm) ...[
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Шинэ машин бүртгэх', style: context.textStyles.h3),
                    const SizedBox(height: 4),
                    Text(
                      _noPlate
                          ? 'Дугааргүй машин — VIN заавал'
                          : 'Дугаар "${_plateCtrl.text.trim().toUpperCase()}" олдсонгүй',
                      style: context.textStyles.caption,
                    ),
                    if (_hurFound) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.good.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(
                            AppDimens.radiusSM,
                          ),
                          border: Border.all(
                            color: context.colors.good.withOpacity(0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.verified_outlined,
                              color: context.colors.good,
                              size: 15,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'ХУР-аас мэдээлэл автоматаар бөглөгдлөө',
                              style: context.textStyles.caption.copyWith(
                                color: context.colors.good,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Divider(height: 24),

                    Text(
                      'Машины мэдээлэл',
                      style: context.textStyles.captionMedium,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            label: 'Марка *',
                            hint: 'Toyota',
                            controller: _makeCtrl,
                            errorText: _vehicleErrors['make'],
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppTextField(
                            label: 'Загвар *',
                            hint: 'Prius',
                            controller: _modelCtrl,
                            errorText: _vehicleErrors['model'],
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            label: 'Он',
                            hint: '2018',
                            controller: _yearCtrl,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            errorText: _vehicleErrors['year'],
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppTextField(
                            label: _noPlate ? 'VIN *' : 'VIN',
                            hint: _noPlate ? 'Заавал' : 'Заавал биш',
                            controller: _vinCtrl,
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[A-Za-z0-9-]'),
                              ),
                              const UpperCaseTextFormatter(),
                            ],
                            errorText: _vehicleErrors['vin'],
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AppTextField(
                      label: 'Явсан км',
                      hint: '0',
                      controller: _mileageCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(kMileageMaxDigits),
                      ],
                      errorText: _vehicleErrors['mileage'],
                      onChanged: (_) => setState(() {}),
                    ),
                    const Divider(height: 24),

                    // ─── Customer: search first, then create ─────────────────
                    Text(
                      'Үйлчлүүлэгч',
                      style: context.textStyles.captionMedium,
                    ),
                    const SizedBox(height: 10),
                    AppTextField(
                      label: 'Нэр эсвэл утасны дугаараар хайх',
                      hint: 'Бат, 99001122...',
                      controller: _custSearchCtrl,
                      onChanged: _searchCustomers,
                      suffixIcon: _searchingCustomers
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
                    if (_customerResults.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ..._customerResults
                          .take(5)
                          .map(
                            (c) => GestureDetector(
                              onTap: () => setState(() {
                                _selectedCustomer = c;
                                _customerResults = [];
                                _custSearchCtrl.clear();
                              }),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: context.colors.surface,
                                  borderRadius: BorderRadius.circular(
                                    AppDimens.radiusSM,
                                  ),
                                  border: Border.all(
                                    color: context.colors.divider,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.person_outline,
                                      color: context.colors.textSecondary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c.displayName,
                                            style:
                                                context.textStyles.bodyMedium,
                                          ),
                                          Text(
                                            c.phone,
                                            style: context.textStyles.caption,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.add,
                                      color: context.colors.accent,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                    ],
                    if (_selectedCustomer != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.accent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(
                            AppDimens.radiusSM,
                          ),
                          border: Border.all(
                            color: context.colors.accent.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              color: context.colors.accent,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedCustomer!.displayName,
                                    style: context.textStyles.bodyMedium
                                        .copyWith(color: context.colors.accent),
                                  ),
                                  Text(
                                    _selectedCustomer!.phone,
                                    style: context.textStyles.caption,
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedCustomer = null),
                              child: Icon(
                                Icons.close,
                                color: context.colors.textSecondary,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'эсвэл шинээр бүртгэх',
                              style: context.textStyles.caption,
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 10),
                      AppTextField(
                        label: 'Овог нэр *',
                        hint: 'Бат',
                        controller: _custNameCtrl,
                        maxLength: 100,
                        errorText: _customerErrors['fullName'],
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 10),
                      AppTextField(
                        label: 'Утасны дугаар *',
                        hint: '99001122',
                        controller: _custPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        errorText: _customerErrors['phone'],
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                    const SizedBox(height: 16),

                    if (_createError != null) ...[
                      Text(
                        _createError!,
                        style: context.textStyles.caption.copyWith(
                          color: context.colors.danger,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_vehicleErrors['plate'] != null) ...[
                      Text(
                        _vehicleErrors['plate']!,
                        style: context.textStyles.caption.copyWith(
                          color: context.colors.danger,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_vehicleErrors['customerId'] != null) ...[
                      Text(
                        _vehicleErrors['customerId']!,
                        style: context.textStyles.caption.copyWith(
                          color: context.colors.danger,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    SizedBox(
                      width: double.infinity,
                      child: AppButton(
                        label: _creating
                            ? 'Бүртгэж байна...'
                            : 'Бүртгэж үргэлжлүүлэх',
                        onPressed: _canCreate && !_creating ? _create : null,
                        loading: _creating,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  bool get _canCreate =>
      (_noPlate
          ? _vinCtrl.text.trim().isNotEmpty
          : _plateCtrl.text.trim().isNotEmpty) &&
      _makeCtrl.text.trim().isNotEmpty &&
      _modelCtrl.text.trim().isNotEmpty &&
      (_selectedCustomer != null ||
          (_custNameCtrl.text.trim().isNotEmpty &&
              _custPhoneCtrl.text.trim().isNotEmpty));
}

// ─── АЛХАМ 2: Динамик checklist ───────────────────────────────────────────────

/// One answerable input: an item, or one position of a positioned item.
typedef _Field = ({TemplateItem item, String key});

/// The visible, answerable inputs of [section] (signatures have no input).
List<_Field> _fieldsOf(NewInspectionController prov, TemplateSection section) {
  final fields = <_Field>[];
  for (final item in section.items) {
    if (!prov.isItemVisible(item) || item.type == ItemType.signature) continue;
    final positions = item.positionSet?.positions;
    if (positions == null) {
      fields.add((item: item, key: item.id));
    } else {
      for (final pos in positions) {
        fields.add((item: item, key: positionedKey(item.id, pos.code)));
      }
    }
  }
  return fields;
}

/// Every visible input of [section] answered (an empty section is not).
bool _isComplete(NewInspectionController prov, TemplateSection section) {
  final fields = _fieldsOf(prov, section);
  return fields.isNotEmpty && fields.every((f) => _isAnswered(prov, f));
}

bool _isAnswered(NewInspectionController prov, _Field f) =>
    f.item.type == ItemType.photo
    ? prov.getPhotos(f.key).isNotEmpty
    : (prov.getAnswer(f.key)?.trim().isNotEmpty ?? false);

/// Tenant-app design (Оношилгоо): one section at a time — progress, section
/// chips, item cards with a segmented status, «Өмнөх» / «Дараах хэсэг».
/// Search (web diagnostic-form parity) lists matching questions from every
/// section instead.
class _ChecklistStep extends StatefulWidget {
  const _ChecklistStep();

  @override
  State<_ChecklistStep> createState() => _ChecklistStepState();
}

class _ChecklistStepState extends State<_ChecklistStep> {
  // Асуултын үгээр хайх (web diagnostic-form-тай ижил). Хариулт controller-т
  // хадгалагддаг тул тохирохгүй мөрийг жагсаалтаас хасахад алдагдахгүй.
  final _search = TextEditingController();
  final _scroll = ScrollController();
  bool _searching = false;
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _closeSearch() => setState(() {
    _searching = false;
    _search.clear();
    _q = '';
  });

  /// Section changes start at the top of the new section.
  void _go(VoidCallback move) {
    move();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<void> _openBulkSheet(
    NewInspectionController prov,
    List<String> options,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Бүх асуултыг:', style: context.textStyles.h3),
            ),
            for (final opt in options)
              ListTile(
                leading: Icon(
                  _optionIcon(opt),
                  color: _optionTone(opt)
                      .foreground(CarserviceTheme.of(context)),
                ),
                title: Text(opt),
                onTap: () => Navigator.of(context).pop(opt),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) prov.markAll(picked);
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<NewInspectionController>();
    final t = CarserviceTheme.of(context);
    final sections = prov.sections;
    final subtitle = _vehicleLine(prov);
    final globalOptions = prov.bulkOptionsFor();

    final header = _StepHeader(
      title: 'Оношилгоо',
      subtitle: subtitle,
      actions: [
        if (sections.isNotEmpty)
          OpsCircleButton(
            icon: _searching ? Icons.close_rounded : Icons.search_rounded,
            tooltip: _searching ? 'Хайлт хаах' : 'Асуулт хайх',
            onPressed: _searching
                ? _closeSearch
                : () => setState(() => _searching = true),
          ),
        if (globalOptions.isNotEmpty)
          OpsCircleButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'Бүх асуултыг тэмдэглэх',
            onPressed: () => _openBulkSheet(prov, globalOptions),
          ),
      ],
    );

    if (sections.isEmpty) {
      return Scaffold(
        backgroundColor: t.shellBackground,
        body: SafeArea(
          child: Column(
            children: [
              header,
              const Expanded(child: Center(child: Text('Хэсэг байхгүй'))),
            ],
          ),
        ),
      );
    }

    final index = prov.currentSection.clamp(0, sections.length - 1);
    final section = sections[index];
    final allFields = [for (final s in sections) ..._fieldsOf(prov, s)];
    final done = allFields.where((f) => _isAnswered(prov, f)).length;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final List<Widget> content;
    if (_searching) {
      content = _searchResults(context, prov, sections);
    } else {
      final visible = section.items.where(prov.isItemVisible).toList();
      final options = prov.bulkOptionsFor([section]);
      content = [
        if (options.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _BulkButtons(
              label: 'Бүгдийг:',
              options: options,
              onMark: (v) => prov.markAll(v, [section]),
            ),
          ),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'Энэ хэсэгт бөглөх асуулт алга.',
              textAlign: TextAlign.center,
              style: context.textStyles.caption,
            ),
          ),
        for (final item in visible)
          KeyedSubtree(
            key: ValueKey(item.id),
            child: _ItemWidget(item: item, prov: prov),
          ),
      ];
    }

    final last = !prov.canGoNext;
    return Scaffold(
      backgroundColor: t.shellBackground,
      extendBody: true,
      bottomNavigationBar: OpsBottomActionBar(
        children: [
          OpsSecondaryButton(
            label: 'Өмнөх',
            onPressed: !_searching && prov.canGoPrev
                ? () => _go(prov.prevSection)
                : null,
          ),
          Expanded(
            child: last || _searching
                ? OpsPrimaryButton(
                    label: 'Дуусгах',
                    onPressed: () => AppNav.to(
                      ChangeNotifierProvider.value(
                        value: prov,
                        child: const _NoteStep(),
                      ),
                    ),
                  )
                : OpsPrimaryButton(
                    label: 'Дараах хэсэг →',
                    dark: true,
                    onPressed: () => _go(prov.nextSection),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                  style: TextStyle(fontSize: 15, color: t.ink),
                  decoration: _filledDecoration(context, hint: 'Асуулт хайх')
                      .copyWith(
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: _SectionProgress(
                  sections: sections,
                  index: index,
                  done: done,
                  total: allFields.length,
                  sectionDone: [for (final s in sections) _isComplete(prov, s)],
                  onSelect: (i) => _go(() => prov.goToSection(i)),
                ),
              ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(20, 14, 20, bottomInset + 16),
                children: content,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _searchResults(
    BuildContext context,
    NewInspectionController prov,
    List<TemplateSection> sections,
  ) {
    final results = <Widget>[];
    for (final section in sections) {
      final matching = section.items
          .where(prov.isItemVisible)
          .where((i) => _q.isEmpty || i.label.toLowerCase().contains(_q))
          .toList();
      if (matching.isEmpty) continue;
      results.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: OpsSectionLabel(section.title),
        ),
      );
      for (final item in matching) {
        results.add(
          KeyedSubtree(
            key: ValueKey(item.id),
            child: _ItemWidget(item: item, prov: prov),
          ),
        );
      }
    }
    if (results.isEmpty) {
      results.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text(
            '«${_search.text.trim()}» гэсэн асуулт олдсонгүй.',
            textAlign: TextAlign.center,
            style: context.textStyles.caption,
          ),
        ),
      );
    }
    return results;
  }
}

/// "Lexus RX 450h · 9012 УКА", or the template name before a vehicle is set.
String _vehicleLine(NewInspectionController prov) {
  final vehicle = prov.vehicle;
  if (vehicle == null) return prov.template?.name ?? '';
  return [
    vehicle.displayName,
    plateLabel(vehicle.plate, vehicle.vin),
  ].where((s) => s.trim().isNotEmpty).join(' · ');
}

/// Round back button, title, mono subtitle, trailing round actions.
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.title,
    this.subtitle = '',
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          OpsCircleButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Буцах',
            onPressed: () => AppNav.back(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: opsMono(context),
                  ),
              ],
            ),
          ),
          for (final action in actions) ...[const SizedBox(width: 8), action],
        ],
      ),
    );
  }
}

/// "ТООРМОСНЫ СИСТЕМ · 2/5", answered counter, bar and section chips; the
/// current chip is scrolled into view.
class _SectionProgress extends StatefulWidget {
  const _SectionProgress({
    required this.sections,
    required this.index,
    required this.done,
    required this.total,
    required this.sectionDone,
    required this.onSelect,
  });

  final List<TemplateSection> sections;
  final int index;
  final int done;
  final int total;
  final List<bool> sectionDone;
  final ValueChanged<int> onSelect;

  @override
  State<_SectionProgress> createState() => _SectionProgressState();
}

class _SectionProgressState extends State<_SectionProgress> {
  final _currentChip = GlobalKey();

  @override
  void initState() {
    super.initState();
    _revealCurrent(animate: false);
  }

  @override
  void didUpdateWidget(_SectionProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _revealCurrent(animate: true);
  }

  void _revealCurrent({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _currentChip.currentContext;
      if (!mounted || chip == null) return;
      Scrollable.ensureVisible(
        chip,
        alignment: 0.5,
        duration: animate ? const Duration(milliseconds: 220) : Duration.zero,
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final sections = widget.sections;
    final index = widget.index;
    final done = widget.done;
    final total = widget.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OpsSectionLabel(
                '${sections[index].title} · ${index + 1}/${sections.length}',
              ),
            ),
            const SizedBox(width: 8),
            Text('$done / $total', style: opsMono(context)),
          ],
        ),
        const SizedBox(height: 8),
        OpsProgressBar(
          value: total == 0 ? 0 : done / total,
          height: 6,
          color: t.ink,
          trackColor: t.border,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 34,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  KeyedSubtree(
                    key: i == index
                        ? _currentChip
                        : ValueKey('inspection_section_$i'),
                    child: _SectionChip(
                      label: sections[i].title,
                      current: i == index,
                      done: widget.sectionDone[i],
                      onTap: () => widget.onSelect(i),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.label,
    required this.current,
    required this.done,
    required this.onTap,
  });

  final String label;
  final bool current;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final (bg, fg, border) = current
        ? (t.ink, t.shellBackground, t.ink)
        : done
        ? (OpsTone.ok.background(t), t.ok, OpsTone.ok.background(t))
        : (t.panel, t.mutedText, t.border);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      side: BorderSide(color: border),
    );
    return Semantics(
      selected: current,
      button: true,
      child: Material(
        color: bg,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (done && !current) ...[
                  Icon(Icons.check_rounded, size: 14, color: fg),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: current ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
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

class _BulkButtons extends StatelessWidget {
  final String label;
  final List<String> options;
  final ValueChanged<String> onMark;
  const _BulkButtons({
    required this.label,
    required this.options,
    required this.onMark,
  });

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        Text(label, style: context.textStyles.caption),
        for (final opt in options)
          ActionChip(
            label: Text(opt),
            visualDensity: VisualDensity.compact,
            backgroundColor: t.panel,
            side: BorderSide(color: t.border),
            shape: const StadiumBorder(),
            labelStyle: TextStyle(fontSize: 12, color: t.ink),
            onPressed: () => onMark(opt),
          ),
      ],
    );
  }
}

/// Status tone of a check option: OK / Хэвийн → ok, Анхаарах → warn,
/// Засах → accent; any other template option is neutral.
OpsTone _optionTone(String option) => switch (option) {
  'Засах' => OpsTone.accent,
  'Анхаарах' => OpsTone.warn,
  'OK' || 'Хэвийн' => OpsTone.ok,
  _ => OpsTone.neutral,
};

IconData _optionIcon(String option) => switch (_optionTone(option)) {
  OpsTone.accent => Icons.build_circle_outlined,
  OpsTone.warn => Icons.error_outline_rounded,
  OpsTone.ok => Icons.check_circle_outline_rounded,
  _ => Icons.radio_button_unchecked_rounded,
};

/// Filled input of the design's cards (notes, text and number answers).
InputDecoration _filledDecoration(BuildContext context, {String? hint}) {
  final t = CarserviceTheme.of(context);
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: t.shellBackground,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: border(t.border),
    enabledBorder: border(t.border),
    focusedBorder: border(t.ink, 1.5),
  );
}

class _ItemWidget extends StatelessWidget {
  final TemplateItem item;
  final NewInspectionController prov;
  const _ItemWidget({required this.item, required this.prov});

  @override
  Widget build(BuildContext context) {
    // Positioned item — байрлал тус бүрд тусдаа input
    if (item.positionSet != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _PositionedItemWidget(item: item, prov: prov),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OpsCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ItemTitle(item: item),
            const SizedBox(height: 10),
            _ItemInput(item: item, prov: prov, fieldKey: item.id),
            if (item.type != ItemType.photo && item.type != ItemType.signature)
              _NoteField(prov: prov, fieldKey: item.id),
          ],
        ),
      ),
    );
  }
}

class _ItemTitle extends StatelessWidget {
  const _ItemTitle({required this.item, this.trailing});

  final TemplateItem item;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            item.label + (item.required ? ' *' : ''),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: t.ink,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(trailing!, style: opsMono(context)),
        ],
      ],
    );
  }
}

/// The answer control for one field, by item type.
class _ItemInput extends StatelessWidget {
  const _ItemInput({
    required this.item,
    required this.prov,
    required this.fieldKey,
  });

  final TemplateItem item;
  final NewInspectionController prov;
  final String fieldKey;

  @override
  Widget build(BuildContext context) => switch (item.type) {
    ItemType.check => _CheckInput(item: item, prov: prov, fieldKey: fieldKey),
    ItemType.text => _TextInput(item: item, prov: prov, fieldKey: fieldKey),
    ItemType.number => _NumberInput(item: item, prov: prov, fieldKey: fieldKey),
    ItemType.photo => _PhotoInput(item: item, prov: prov, fieldKey: fieldKey),
    ItemType.signature => Text(
      '(Гарын үсэг — тэмдэглэл орлуулна)',
      style: context.textStyles.caption,
    ),
  };
}

// Positioned item — байрлал тус бүр нь тусдаа мөр
class _PositionedItemWidget extends StatelessWidget {
  final TemplateItem item;
  final NewInspectionController prov;
  const _PositionedItemWidget({required this.item, required this.prov});

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final positions = item.positionSet!.positions;
    final answered = positions
        .where(
          (p) => _isAnswered(prov, (
            item: item,
            key: positionedKey(item.id, p.code),
          )),
        )
        .length;

    return OpsCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ItemTitle(
            item: item,
            trailing: item.type == ItemType.signature
                ? null
                : '$answered/${positions.length}',
          ),
          for (final (i, pos) in positions.indexed) ...[
            if (i > 0) Divider(height: 24, color: t.shellBackground),
            if (i == 0) const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: t.shellBackground,
                  borderRadius: BorderRadius.circular(AppDimens.radiusFull),
                ),
                child: Text(
                  pos.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _ItemInput(
              item: item,
              prov: prov,
              fieldKey: positionedKey(item.id, pos.code),
            ),
            if (item.type != ItemType.signature)
              _NoteField(
                prov: prov,
                fieldKey: positionedKey(item.id, pos.code),
              ),
          ],
        ],
      ),
    );
  }
}

/// Segmented status control: one equal-width segment per option (wraps when
/// a template has many). Selected: OK solid green, Анхаарах warn tint,
/// Засах solid accent.
class _CheckInput extends StatelessWidget {
  final TemplateItem item;
  final NewInspectionController prov;
  final String fieldKey;
  const _CheckInput({
    required this.item,
    required this.prov,
    required this.fieldKey,
  });

  @override
  Widget build(BuildContext context) {
    final options = item.effectiveOptions;
    final selected = prov.getAnswer(fieldKey);
    Widget segment(String opt) => _Segment(
      label: opt,
      tone: _optionTone(opt),
      selected: selected == opt,
      onTap: () => prov.setAnswer(fieldKey, opt),
    );

    if (options.length > 4) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final opt in options) IntrinsicWidth(child: segment(opt)),
        ],
      );
    }
    return Row(
      children: [
        for (final (i, opt) in options.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: segment(opt)),
        ],
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final OpsTone tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final (Color bg, Color fg, Color border) = !selected
        ? (t.panel, t.mutedText, t.border)
        : switch (tone) {
            // The dark theme's ok green is light: dark text on it.
            OpsTone.ok => (
              t.ok,
              ThemeData.estimateBrightnessForColor(t.ok) == Brightness.light
                  ? OpsColors.darkCarbon
                  : t.onAccent,
              t.ok,
            ),
            OpsTone.accent => (t.accent, t.onAccent, t.accent),
            OpsTone.warn => (
              OpsTone.warn.background(t),
              t.warn,
              t.warn.withValues(alpha: 0.45),
            ),
            _ => (t.ink, t.shellBackground, t.ink),
          };
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: border),
    );
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: bg,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
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

class _TextInput extends StatelessWidget {
  final TemplateItem item;
  final NewInspectionController prov;
  final String fieldKey;
  const _TextInput({
    required this.item,
    required this.prov,
    required this.fieldKey,
  });

  @override
  Widget build(BuildContext context) {
    return _ControlledTextField(
      key: ValueKey('answer:$fieldKey'),
      initialText: prov.getAnswer(fieldKey) ?? '',
      onChanged: (v) => prov.setAnswer(fieldKey, v),
      decoration: _filledDecoration(context, hint: 'Утга оруулна уу...'),
      style: TextStyle(fontSize: 14, color: CarserviceTheme.of(context).ink),
    );
  }
}

class _NumberInput extends StatelessWidget {
  final TemplateItem item;
  final NewInspectionController prov;
  final String fieldKey;
  const _NumberInput({
    required this.item,
    required this.prov,
    required this.fieldKey,
  });

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return _ControlledTextField(
      key: ValueKey('answer:$fieldKey'),
      initialText: prov.getAnswer(fieldKey) ?? '',
      onChanged: (v) => prov.setAnswer(fieldKey, v),
      decoration: _filledDecoration(context, hint: '0'),
      style: TextStyle(
        fontFamily: t.monoFontFamily,
        fontSize: 14,
        color: t.ink,
      ),
      keyboardType: TextInputType.number,
    );
  }
}

/// Controller-ийг State дотор нэг л удаа үүсгэнэ. build бүрт шинэ
/// TextEditingController үүсгэвэл курсор 0 руу үсэрч, бичсэн үг урвуу гардаг.
class _ControlledTextField extends StatefulWidget {
  final String initialText;
  final ValueChanged<String> onChanged;
  final InputDecoration decoration;
  final TextStyle? style;
  final TextInputType? keyboardType;
  final int? minLines;
  final int maxLines;
  final bool autofocus;
  const _ControlledTextField({
    super.key,
    required this.initialText,
    required this.onChanged,
    required this.decoration,
    this.style,
    this.keyboardType,
    this.minLines,
    this.maxLines = 1,
    this.autofocus = false,
  });

  @override
  State<_ControlledTextField> createState() => _ControlledTextFieldState();
}

class _ControlledTextFieldState extends State<_ControlledTextField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      decoration: widget.decoration,
      style: widget.style,
      keyboardType: widget.keyboardType,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
    );
  }
}

// ─── АЛХАМ 3: Нэмэлт мэдээлэл + илгээх ──────────────────────────────────────

class _NoteStep extends StatefulWidget {
  const _NoteStep();

  @override
  State<_NoteStep> createState() => _NoteStepState();
}

class _NoteStepState extends State<_NoteStep> {
  final _mileageCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _mileageCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<NewInspectionController>();
    final t = CarserviceTheme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: t.shellBackground,
      extendBody: true,
      bottomNavigationBar: OpsBottomActionBar(
        children: [
          Expanded(
            child: OpsPrimaryButton(
              label: prov.submitting ? 'Илгээж байна...' : 'Тайлан илгээх',
              onPressed: prov.submitting ? null : () => _submit(context),
            ),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StepHeader(title: 'Нэмэлт мэдээлэл', subtitle: _vehicleLine(prov)),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 14, 20, bottomInset + 16),
                children: [
                  // ─── Дүн ──────────────────────────────────────────────────
                  OpsCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const OpsSectionLabel('Оношилгооны дүн'),
                        const SizedBox(height: 12),
                        StatCounterRow(
                          good: prov.answeredGood,
                          warning: prov.answeredWarning,
                          danger: prov.answeredDanger,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ─── Машины мэдээлэл ──────────────────────────────────────
                  OpsCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const OpsSectionLabel('Машин'),
                        const SizedBox(height: 10),
                        if (prov.vehicle != null) ...[
                          _SummaryRow(
                            label: 'Дугаар',
                            value: plateLabel(
                              prov.vehicle!.plate,
                              prov.vehicle!.vin,
                            ),
                          ),
                          _SummaryRow(
                            label: 'Марка',
                            value: prov.vehicle!.displayName,
                          ),
                        ],
                        if (prov.customer != null)
                          _SummaryRow(
                            label: 'Үйлчлүүлэгч',
                            value: prov.customer!.displayName,
                          ),
                        const SizedBox(height: 12),
                        AppTextField(
                          label: 'Явсан км',
                          hint: '0',
                          controller: _mileageCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(
                              kMileageMaxDigits + 2,
                            ),
                          ],
                          onChanged: (v) => prov.setMileage(
                            int.tryParse(v.replaceAll(',', '')) ?? 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ─── Тайлбар ──────────────────────────────────────────────
                  OpsCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const OpsSectionLabel('Нийт тайлбар'),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _noteCtrl,
                          minLines: 3,
                          maxLines: 6,
                          decoration: _filledDecoration(
                            context,
                            hint: 'Нэмэлт тайлбар...',
                          ),
                          style: TextStyle(fontSize: 14, color: t.ink),
                          onChanged: prov.setGeneralNote,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final prov = context.read<NewInspectionController>();
    final user = Authenticator.user;
    // Working branch first — the server 403s a report filed under a branch
    // other than the `X-Working-Branch` scope.
    final branchId = workingBranchIdOf(context) ?? user?.branchId ?? '';

    if (branchId.isEmpty) {
      // Салбар байхгүй бол эхний салбарыг авна
      final branches = await DiagnosticService.getBranches();
      if (branches.isEmpty) {
        return;
      }
      final id = await prov.submit(branches.first.id);
      if (!context.mounted) return;
      _onSuccess(context, prov, id);
    } else {
      final id = await prov.submit(branchId);
      if (!context.mounted) return;
      _onSuccess(context, prov, id);
    }
  }

  void _onSuccess(
    BuildContext context,
    NewInspectionController prov,
    String? reportId,
  ) {
    if (reportId == null) return;
    // InspectionController-г reload хийнэ
    context.read<InspectionController>().loadReports();
    // Дэлгэрэнгүй дэлгэц рүү шилжинэ
    // Захиалгаас нээсэн бол зөвхөн маягтын алхмуудыг хаана — back дарахад
    // тухайн захиалгын дэлгэрэнгүй рүү буцна. Үгүй бол эхний дэлгэц хүртэл.
    var passedForm = false;
    AppNav.offUntil(ReportDetailScreen(reportId: reportId), (route) {
      if (route.isFirst || passedForm) return true;
      if (prov.fromOrder && route.settings.name == _orderFormRouteName) {
        passedForm = true;
      }
      return false;
    });
  }
}

// Leading slash: GetX adds one to every route name it pushes.
const _orderFormRouteName = '/order-diagnostic-form';

// ─── Photo input widget ────────────────────────────────────────────────────────

class _PhotoInput extends StatefulWidget {
  final TemplateItem item;
  final NewInspectionController prov;
  final String fieldKey;
  const _PhotoInput({
    required this.item,
    required this.prov,
    required this.fieldKey,
  });

  @override
  State<_PhotoInput> createState() => _PhotoInputState();
}

class _PhotoInputState extends State<_PhotoInput> {
  final _picker = ImagePicker();

  Future<void> _pick() async {
    final picked = await _picker.pickMultiImage(
      imageQuality: uploadImageQuality,
      maxWidth: uploadMaxDimension,
      maxHeight: uploadMaxDimension,
    );
    final images = await filterUploadable(picked);
    for (final img in images.accepted) {
      widget.prov.addPhoto(widget.fieldKey, img.path);
    }
    if (images.rejected > 0) messageWarning(uploadTooLargeMessage);
  }

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    final photos = widget.prov.getPhotos(widget.fieldKey);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, path) in photos.indexed) ...[
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(path),
                    width: 76,
                    height: 76,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Semantics(
                    button: true,
                    label: 'Зураг устгах',
                    child: GestureDetector(
                      onTap: () => widget.prov.removePhoto(widget.fieldKey, i),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: OpsDark.bg.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: OpsDark.ink,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
          Tooltip(
            message: 'Зураг нэмэх',
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _pick,
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(
                  painter: _DashedBorderPainter(
                    color: t.mutedText3,
                    radius: 12,
                  ),
                  child: SizedBox(
                    width: 76,
                    height: 76,
                    child: Icon(
                      Icons.photo_camera_outlined,
                      color: t.ink,
                      size: 22,
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

/// Dashed rounded outline of the "add photo" tile.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.75),
          Radius.circular(radius),
        ),
      );
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

// ─── Note field ───────────────────────────────────────────────────────────────

/// «+ Тэмдэглэл» until opened (already open when the field has a note), then
/// the design's ТЭМДЭГЛЭЛ textarea.
class _NoteField extends StatefulWidget {
  final NewInspectionController prov;
  final String fieldKey;
  const _NoteField({required this.prov, required this.fieldKey});

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  late bool _open = widget.prov.getNote(widget.fieldKey)?.isNotEmpty ?? false;
  bool _openedByTap = false;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    if (!_open) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() {
              _open = true;
              _openedByTap = true;
            }),
            style: TextButton.styleFrom(
              foregroundColor: t.mutedText,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Тэмдэглэл', style: TextStyle(fontSize: 13)),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OpsSectionLabel('Тэмдэглэл'),
          const SizedBox(height: 6),
          _ControlledTextField(
            key: ValueKey('note:${widget.fieldKey}'),
            initialText: widget.prov.getNote(widget.fieldKey) ?? '',
            onChanged: (v) => widget.prov.setNote(widget.fieldKey, v),
            decoration: _filledDecoration(
              context,
              hint: 'Тайлбар (заавал биш)...',
            ),
            minLines: 2,
            maxLines: 4,
            autofocus: _openedByTap,
            style: TextStyle(fontSize: 14, color: t.ink),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: context.textStyles.caption),
          ),
          Expanded(child: Text(value, style: context.textStyles.bodyMedium)),
        ],
      ),
    );
  }
}
