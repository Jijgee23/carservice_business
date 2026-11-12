import 'package:carservice_business/core/utils/vehicle_plate.dart';
import 'package:carservice_business/app/shell/shell_chrome.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:intl/intl.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/widgets/org_badge.dart';
import 'package:carservice_business/core/utils/money_format.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/order_item_draft.dart';
import 'package:carservice_business/features/orders/presentation/screens/new_customer_sheet.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_detail_screen.dart'
    show ItemFormScreen;
import 'package:carservice_business/features/vehicles/presentation/screens/vehicle_create_screen.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/services/diagnostic_service.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/domain/order_payment_mode.dart';
import 'package:carservice_business/features/orders/presentation/widgets/payment_mode_selector.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/core/widgets/date_picker/app_date_picker.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:carservice_business/core/widgets/app_dropdown.dart';
import 'package:carservice_business/features/orders/presentation/widgets/assignee_avatar.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_intake_controller.dart';
import 'package:carservice_business/features/orders/presentation/widgets/intake/intake_section.dart';
import 'package:carservice_business/features/orders/presentation/widgets/vehicle_picker_field.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({
    super.key,
    required this.repository,
    this.appointmentId,
    this.initialVehicle,
    this.initialCustomer,
    this.vehicleSearch,
    this.vehicleRegister,
  });

  final OrdersRepository repository;

  /// When set (e.g. opened from the Today board's appointments timeline
  /// after the customer has arrived), the created order is linked to this
  /// appointment via `OrdersRepository.createOrder`'s `appointmentId`.
  /// [initialVehicle] / [initialCustomer] should also be supplied so the
  /// customer and vehicle steps start pre-filled with the appointment's car and
  /// owner — the user can still clear and pick a different one.
  final String? appointmentId;
  final VehicleSummary? initialVehicle;
  final CustomerSummary? initialCustomer;

  /// Test seam for the vehicle search; defaults to
  /// [DiagnosticService.searchVehicles] (plate, make, model, VIN, owner).
  final Future<List<VehicleSummary>> Function(String query)? vehicleSearch;

  /// Test seam for «+ дугаар — машин бүртгэх»; defaults to
  /// [DiagnosticService.registerVehicleFromPlate].
  final PlateRegister? vehicleRegister;

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  // Машин эсвэл харилцагчаас аль нэгээр нь эхэлнэ. Машинаар эхэлбэл
  // харилцагч нь машины эзэмшигч болно: сервер машин сонгосон харилцагчийнх
  // байхыг шаарддаг (`validateOrderReferences`). Хайлтаас эзэмшигчгүй
  // бүртгэсэн машин (VehiclePickerField) харилцагчийг хүлээнэ — хуудас
  // үүсгэхэд сервер түүнд холбоно.

  /// The customer was taken from the picked vehicle's owner: clearing the
  /// vehicle clears them too, and they can't be changed on their own.
  bool _customerFromVehicle = false;

  // Харилцагч — эхлээд харилцагч сонговол дараа нь түүний машин.
  final _customerCtrl = TextEditingController();
  List<CustomerSummary> _customerResults = [];
  bool _searchingCustomer = false;
  CustomerSummary? _customer;
  Timer? _customerTimer;

  // 2. Машин — сонгосон харилцагчийн машинууд
  List<VehicleSummary> _customerVehicles = [];
  bool _loadingVehicles = false;
  VehicleSummary? _vehicle;
  OrderPaymentMode _paymentMode = OrderPaymentMode.regular;
  int _vehiclesSeq = 0;

  // Branch + schedule + notes
  List<BranchSummary> _branches = [];
  BranchSummary? _branch;
  DateTime? _scheduledAt;
  int? _estimatedDurationMinutes;
  final _notesCtrl = TextEditingController();
  bool _submitting = false;
  late final OrderIntakeController _intake;

  // Хариуцах мастер — `orders.assign` эрхтэй хэрэглэгчид заавал, сонгосон
  // салбараар шүүгдэнэ. Зөвхөн `orders.assign` эрхтэй хэрэглэгчид харагдана
  // (сервер ч мөн адил шаарддаг).
  List<AssignableUser> _assignees = [];
  bool _loadingAssignees = false;
  String? _assigneeError;
  AssignableUser? _assignee;
  String? _assigneeFieldError;
  int _assigneesSeq = 0;

  // Ажил, сэлбэг — сангаас сонгосон эсвэл гараар бүртгэсэн мөрүүд. Үүсгэх
  // хүсэлт мөр хүлээж авдаггүй тул хуудас үүссэний дараа нэг нэгээр нэмнэ.
  final List<OrderItemDraft> _items = [];

  final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    _customer = widget.initialCustomer ?? widget.initialVehicle?.customer;
    _vehicle = widget.initialVehicle;
    _paymentMode = OrderPaymentMode.forVehicle(_vehicle?.isPostpaid ?? false);
    if (_vehicle != null) _customerVehicles = [_vehicle!];
    if (_customer != null) _loadCustomerVehicles(_customer!.id);
    _loadBranches();
    _notesCtrl.addListener(() => setState(() {}));
    _intake = OrderIntakeController(widget.repository)
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _customerTimer?.cancel();
    _customerCtrl.dispose();
    _notesCtrl.dispose();
    _intake.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    final branches = await DiagnosticService.getBranches();
    if (!mounted) return;
    final branchId = Authenticator.user?.branchId;
    final before = _branch;
    setState(() {
      _branches = branches;
      if (branchId != null) {
        try {
          _branch = branches.firstWhere((b) => b.id == branchId);
        } catch (_) {
          _branch = branches.isNotEmpty ? branches.first : null;
        }
      } else if (branches.isNotEmpty) {
        _branch = branches.first;
      }
    });
    if (_branch != before) _loadAssignees();
  }

  bool get _canAssign {
    final user = Authenticator.user;
    return user?.isOwner == true ||
        user?.role?.permissions.contains('orders.assign') == true;
  }

  bool _hasPermission(String permission) {
    final user = Authenticator.user;
    return user?.isOwner == true ||
        user?.role?.permissions.contains(permission) == true;
  }

  /// Lines need edit rights on the new order (server `canEditOrder`):
  /// `orders.edit`, or `orders.editOwn` on an order assigned to the user.
  bool get _mayAddItems =>
      _hasPermission('orders.edit') || _hasPermission('orders.editOwn');

  /// [_mayAddItems] for the chosen master: without `orders.assign` the server
  /// assigns the order to its creator.
  bool get _canAddItems =>
      _hasPermission('orders.edit') ||
      (_hasPermission('orders.editOwn') &&
          (!_canAssign || _assignee?.id == Authenticator.user?.id));

  /// Without `orders.itemPrice` the server takes the catalog price and
  /// refuses hand-entered lines (`ITEM_PRICE_FORBIDDEN`).
  bool get _canItemPrice => _hasPermission('orders.itemPrice');

  /// Staged lines the server would refuse: a master other than the user was
  /// chosen by someone who may only edit their own orders.
  String? get _itemsBlockedHint => _items.isNotEmpty && !_canAddItems
      ? 'Өөрт оноосон хуудсанд л ажил нэмэх эрхтэй'
      : null;

  Future<void> _addItem({required bool manual}) async {
    final draft = await AppNav.to<OrderItemDraft>(
      ItemFormScreen.draft(manual: manual, canEditPrice: _canItemPrice),
    );
    if (draft == null || !mounted || _isDuplicateDiagnostic(draft)) return;
    setState(() => _items.add(draft));
  }

  Future<void> _editItem(int index) async {
    final draft = await AppNav.to<OrderItemDraft>(
      ItemFormScreen.draft(
        editDraft: _items[index],
        canEditPrice: _canItemPrice,
      ),
    );
    if (draft == null || !mounted || _isDuplicateDiagnostic(draft, index)) {
      return;
    }
    setState(() => _items[index] = draft);
  }

  /// The server takes a diagnostic once per order (`DUPLICATE_DIAGNOSTIC`).
  bool _isDuplicateDiagnostic(OrderItemDraft draft, [int? except]) {
    final templateId = draft.diagnosticTemplateId;
    if (templateId == null) return false;
    for (final (i, item) in _items.indexed) {
      if (i != except && item.diagnosticTemplateId == templateId) {
        messageWarning('Энэ оношилгоо аль хэдийн нэмэгдсэн байна.');
        return true;
      }
    }
    return false;
  }

  void _selectBranch(BranchSummary b) {
    if (b.id == _branch?.id) return;
    setState(() => _branch = b);
    _loadAssignees();
  }

  Future<void> _loadAssignees() async {
    final branch = _branch;
    if (!_canAssign || branch == null) return;
    final seq = ++_assigneesSeq;
    setState(() {
      _loadingAssignees = true;
      _assigneeError = null;
    });
    final result = await widget.repository.getAssignableUsers(
      branchId: branch.id,
    );
    if (!mounted || seq != _assigneesSeq) return;
    setState(() {
      _loadingAssignees = false;
      switch (result) {
        case Ok(:final value):
          _assignees = value;
          // Салбар солиход тэр салбарт хамаарахгүй мастерыг цэвэрлэнэ.
          final keep = _assignee;
          if (keep != null && !value.any((u) => u.id == keep.id)) {
            _assignee = null;
          }
          // Сервер мастерыг заавал шаарддаг тул нэвтэрсэн хэрэглэгч жагсаалтад
          // байвал урьдчилан сонгоно.
          if (_assignee == null) {
            final me = Authenticator.user?.id;
            for (final u in value) {
              if (u.id == me) {
                _assignee = u;
                break;
              }
            }
          }
        case Err(:final error):
          _assignees = [];
          _assignee = null;
          _assigneeError = error.display;
      }
    });
  }

  void _searchCustomer(String q) {
    _customerTimer?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _customerResults = []);
      return;
    }
    _customerTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _searchingCustomer = true);
      final results = await DiagnosticService.searchCustomers(q.trim());
      if (!mounted) return;
      setState(() {
        _customerResults = results;
        _searchingCustomer = false;
      });
    });
  }

  /// The picker's choice. An owned vehicle with no customer yet brings its
  /// owner (vehicle first); an ownerless one, registered from the search,
  /// waits for the customer the order is created for.
  void _onVehicleChanged(VehicleSummary? v) {
    if (v == null) return _clearVehicle();
    final owner = v.customer;
    if (owner != null && owner.id != _customer?.id) {
      setState(() {
        _vehicle = v;
        _customer = owner;
        _customerFromVehicle = true;
        _customerVehicles = [v];
        _paymentMode = _paymentMode.afterVehicleChange(v.isPostpaid);
      });
      return;
    }
    setState(() {
      _vehicle = v;
      if (_customer != null && !_customerVehicles.any((x) => x.id == v.id)) {
        _customerVehicles = [v, ..._customerVehicles];
      }
      _paymentMode = _paymentMode.afterVehicleChange(v.isPostpaid);
    });
  }

  /// Clears the vehicle; an owner taken from it goes with it, a customer
  /// picked first stays with their vehicles.
  void _clearVehicle() => setState(() {
    _vehicle = null;
    if (_customerFromVehicle) {
      _customer = null;
      _customerFromVehicle = false;
      _customerVehicles = [];
      _loadingVehicles = false;
      _vehiclesSeq++;
    }
  });

  void _selectCustomer(CustomerSummary c) {
    setState(() {
      _customer = c;
      _customerFromVehicle = false;
      // An ownerless vehicle (registered from the search) goes to this
      // customer; any other vehicle belongs to someone else.
      if (_vehicle?.customerId != null) _vehicle = null;
      _customerResults = [];
      _customerCtrl.clear();
    });
    _loadCustomerVehicles(c.id);
  }

  void _clearCustomer() => setState(() {
    _customer = null;
    _customerFromVehicle = false;
    _vehicle = null;
    _customerVehicles = [];
    _loadingVehicles = false;
    _vehiclesSeq++;
  });

  Future<void> _loadCustomerVehicles(String customerId) async {
    final seq = ++_vehiclesSeq;
    setState(() => _loadingVehicles = true);
    final list = await DiagnosticService.vehiclesForCustomer(customerId);
    if (!mounted || seq != _vehiclesSeq) return;
    setState(() {
      // Урьдчилан сонгосон машин (цаг захиалгаас) жагсаалтад заавал харагдана.
      final keep = _vehicle;
      _customerVehicles = keep == null || list.any((v) => v.id == keep.id)
          ? list
          : [keep, ...list];
      _loadingVehicles = false;
      // Ганц машинтай бол шууд сонгоно.
      if (_vehicle == null && list.length == 1) {
        _vehicle = list.first;
        _paymentMode = _paymentMode.afterVehicleChange(list.first.isPostpaid);
      }
    });
  }

  Future<void> _openNewCustomer() async {
    final result = await showNewCustomerSheet(context);
    if (result != null && mounted) _selectCustomer(result);
  }

  Future<void> _openNewVehicle() async {
    final result = await AppNav.to<NewVehicleResult>(
      VehicleCreateScreen(initialCustomer: _customer),
    );
    if (result == null || !mounted) return;
    final owner = result.customer ?? result.vehicle.customer;
    if (owner != null && owner.id != _customer?.id) {
      // Бүртгэх үед өөр эзэмшигч сонгосон бол тэр харилцагч руу шилжинэ.
      // Машинаар эхэлсэн бол (харилцагч сонгоогүй) эзэмшигч нь машинаас.
      final fromVehicle = _customer == null || _customerFromVehicle;
      setState(() {
        _customer = owner;
        _customerFromVehicle = fromVehicle;
        _vehicle = result.vehicle;
        _paymentMode = _paymentMode.afterVehicleChange(
          result.vehicle.isPostpaid,
        );
      });
      _loadCustomerVehicles(owner.id);
      return;
    }
    setState(() {
      _vehicle = result.vehicle;
      _paymentMode = _paymentMode.afterVehicleChange(result.vehicle.isPostpaid);
      if (!_customerVehicles.any((v) => v.id == result.vehicle.id)) {
        _customerVehicles = [..._customerVehicles, result.vehicle];
      }
    });
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final result = await AppDatePicker.dateTime(
      context,
      initial: _scheduledAt ?? DateTime(now.year, now.month, now.day, 9, 0),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (result != null && mounted) setState(() => _scheduledAt = result);
  }

  // Controller-free dialog: a short-lived TextEditingController disposed
  // while the dialog's exit transition still referenced it produced
  // "A TextEditingController was used after being disposed" (fixed
  // elsewhere in this repo — see the status-change duration dialog in
  // order_detail_screen.dart). Capture input in a plain local instead.
  Future<void> _pickDuration() async {
    var input = _estimatedDurationMinutes?.toString() ?? '';
    final result = await AppNav.dialog<int>(
      AlertDialog(
        title: const Text('Ажлын хугацаа'),
        content: TextFormField(
          key: const ValueKey('create_order_duration_input'),
          initialValue: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Минут'),
          onChanged: (value) => input = value,
        ),
        actions: [
          TextButton(
            onPressed: () => AppNav.back(),
            child: const Text('Болих'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(input.trim());
              if (parsed != null && parsed > 0) {
                AppNav.back(parsed);
              }
            },
            child: const Text('Сонгох'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _estimatedDurationMinutes = result);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    final result = await widget.repository.createOrder(
      branchId: _branch!.id,
      customerId: _customer!.id,
      vehicleId: _vehicle!.id,
      assignedToId: _canAssign ? _assignee!.id : null,
      scheduledAt: _scheduledAt,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      estimatedDurationMinutes: _estimatedDurationMinutes,
      appointmentId: widget.appointmentId,
      intake: _intake.draft,
      isPostpaid: _paymentMode.isPostpaid,
      isInternal: _paymentMode.isInternal,
    );
    if (result case Ok(:final value)) {
      // The order exists now: its lines go in even if the screen was left.
      if (_items.isNotEmpty) {
        final added = await addOrderItemDrafts(
          widget.repository,
          value.id,
          List.of(_items),
        );
        if (added.firstError case final error?) {
          messageError(
            '${added.failed} мөр нэмэгдсэнгүй: ${error.display} '
            'Засварын хуудаснаас дахин нэмнэ үү.',
          );
        }
      }
      if (mounted) AppNav.back(value);
      return;
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result case Err(:final error)) {
      final fieldMsg = error.fieldErrors?['assignedToId'];
      if (fieldMsg != null && _canAssign) {
        setState(() => _assigneeFieldError = fieldMsg);
      } else {
        messageError(error.display);
      }
    }
  }

  bool get _canSubmit =>
      _customer != null &&
      _vehicle != null &&
      _branch != null &&
      (!_canAssign || _assignee != null) &&
      _itemsBlockedHint == null &&
      _intake.blockReason == null;

  @override
  Widget build(BuildContext context) {
    // Sections after the branch (3) are numbered by which ones are shown.
    var step = 3;
    return Scaffold(
      backgroundColor: context.opsBackground,
      appBar: AppBar(
        title: Text('Засварын хуудас үүсгэх'),
        actions: const [ShellNotificationBell()],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 1. Машин ───────────────────────────────────────────
                  // Улсын дугаар, марк, эзэмшигчээр хайна; эсвэл эхлээд
                  // харилцагч сонговол түүний машинууд энд гарна.
                  _SectionLabel(
                    number: '1',
                    title: 'Машин сонгох',
                    done: _vehicle != null,
                  ),
                  const SizedBox(height: 10),
                  VehiclePickerField(
                    key: const ValueKey('create_order_vehicle_picker'),
                    value: _vehicle,
                    customer: _customer,
                    customerVehicles: _customerVehicles,
                    loadingCustomerVehicles: _loadingVehicles,
                    search: widget.vehicleSearch,
                    register: widget.vehicleRegister,
                    onChanged: _onVehicleChanged,
                    onRegisterManually: _openNewVehicle,
                  ),
                  if (_vehicle != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Төлбөрийн нөхцөл',
                      style: context.textStyles.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    PaymentModeSelector(
                      key: const ValueKey('create-order-payment-mode'),
                      value: _paymentMode,
                      onChanged: (m) => setState(() => _paymentMode = m),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _paymentMode.helper,
                      key: const ValueKey('create-order-payment-mode-helper'),
                      style: context.textStyles.caption,
                    ),
                  ],
                  const SizedBox(height: 24),

                  // ── 2. Харилцагч ───────────────────────────────────────
                  _SectionLabel(
                    number: '2',
                    title: _customerFromVehicle
                        ? 'Харилцагч · машины эзэмшигч'
                        : 'Харилцагч сонгох',
                    done: _customer != null,
                  ),
                  const SizedBox(height: 10),
                  if (_customerFromVehicle && _customer != null)
                    _VehicleOwnerCard(customer: _customer!)
                  else
                    _CustomerSection(
                      ctrl: _customerCtrl,
                      searching: _searchingCustomer,
                      results: _customerResults,
                      selected: _customer,
                      onSearch: _searchCustomer,
                      onSelect: _selectCustomer,
                      onClear: _clearCustomer,
                      onNewCustomer: _openNewCustomer,
                    ),
                  const SizedBox(height: 24),

                  // ── 3. Салбар ──────────────────────────────────────────
                  _SectionLabel(
                    number: '3',
                    title: 'Салбар',
                    done: _branch != null,
                  ),
                  const SizedBox(height: 10),
                  _BranchSection(
                    branches: _branches,
                    selected: _branch,
                    onSelect: _selectBranch,
                  ),
                  const SizedBox(height: 24),

                  // ── 4. Хариуцах мастер ─────────────────────────────────
                  if (_canAssign) ...[
                    _SectionLabel(
                      number: '${++step}',
                      title: 'Хариуцах мастер',
                      done: _assignee != null,
                    ),
                    const SizedBox(height: 10),
                    _AssigneeSection(
                      users: _assignees,
                      selected: _assignee,
                      loading: _loadingAssignees,
                      error: _assigneeError,
                      fieldError: _assigneeFieldError,
                      onChanged: (u) => setState(() {
                        _assignee = u;
                        _assigneeFieldError = null;
                      }),
                      onRetry: _loadAssignees,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Ажил, сэлбэг: сангаас эсвэл гараар ─────────────────
                  if (_mayAddItems) ...[
                    _SectionLabel(
                      number: '${++step}',
                      title: 'Ажил, сэлбэг',
                      done: _items.isNotEmpty,
                      optional: true,
                    ),
                    const SizedBox(height: 10),
                    _ItemsSection(
                      items: _items,
                      canManual: _canItemPrice,
                      blockedHint: _itemsBlockedHint,
                      onPickCatalog: () => _addItem(manual: false),
                      onAddManual: () => _addItem(manual: true),
                      onEdit: _editItem,
                      onRemove: (i) => setState(() => _items.removeAt(i)),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Нэмэлт ─────────────────────────────────────────────
                  _SectionLabel(
                    number: '${++step}',
                    title: 'Нэмэлт мэдээлэл',
                    done: _scheduledAt != null || _notesCtrl.text.isNotEmpty,
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  _DetailsSection(
                    scheduledAt: _scheduledAt,
                    notesCtrl: _notesCtrl,
                    dateFmt: _dateFmt,
                    onPickDate: _pickSchedule,
                    onClearDate: () => setState(() => _scheduledAt = null),
                    estimatedDurationMinutes: _estimatedDurationMinutes,
                    onPickDuration: _pickDuration,
                    onClearDuration: () =>
                        setState(() => _estimatedDurationMinutes = null),
                  ),
                  const SizedBox(height: 16),

                  // ── Хүлээн авах (зөвхөн үүсгэх үед) ─────────────────────
                  IntakeSection(controller: _intake),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // ── Sticky bottom bar ─────────────────────────────────────────
          _BottomBar(
            customer: _customer,
            vehicle: _vehicle,
            branch: _branch,
            scheduledAt: _scheduledAt,
            dateFmt: _dateFmt,
            itemCount: _items.length,
            blockedHint: _itemsBlockedHint,
            canSubmit: _canSubmit,
            submitting: _submitting,
            onSubmit: _submit,
          ),
        ],
      ),
    );
  }
}

// ─── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String number;
  final String title;
  final bool done;
  final bool optional;
  const _SectionLabel({
    required this.number,
    required this.title,
    this.done = false,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: done ? context.opsGood : context.opsPrimary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: done
                ? Icon(
                    Icons.check_rounded,
                    size: 13,
                    color: context.opsTextOnDark,
                  )
                : Text(
                    number,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.opsTextOnDark,
                    ),
                  ),
          ),
        ),
        SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.h3.copyWith(
              color: done ? context.opsGood : context.opsTextPrimary,
            ),
          ),
        ),
        if (optional) ...[
          SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: context.opsBackground,
              borderRadius: BorderRadius.circular(AppDimens.radiusXS),
            ),
            child: Text(
              'заавал биш',
              style: TextStyle(fontSize: 10, color: context.opsTextHint),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Customer section ──────────────────────────────────────────────────────────

BoxDecoration _cardDecoration(BuildContext context, {Color? border}) =>
    BoxDecoration(
      color: context.opsSurface,
      borderRadius: BorderRadius.circular(AppDimens.radiusMD),
      border: Border.all(color: border ?? context.opsDivider),
      boxShadow: [
        BoxShadow(
          color: context.opsTextPrimary.withOpacity(0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );

class _CustomerSection extends StatelessWidget {
  final TextEditingController ctrl;
  final bool searching;
  final List<CustomerSummary> results;
  final CustomerSummary? selected;
  final ValueChanged<String> onSearch;
  final ValueChanged<CustomerSummary> onSelect;
  final VoidCallback onClear;
  final VoidCallback onNewCustomer;

  const _CustomerSection({
    required this.ctrl,
    required this.searching,
    required this.results,
    required this.selected,
    required this.onSearch,
    required this.onSelect,
    required this.onClear,
    required this.onNewCustomer,
  });

  @override
  Widget build(BuildContext context) {
    if (selected != null) {
      return Container(
        key: const ValueKey('create_order_selected_customer'),
        decoration: _cardDecoration(
          context,
          border: context.opsAccent.withOpacity(0.35),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: context.opsAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppDimens.radiusMD),
              ),
              child: Icon(
                Icons.person_rounded,
                color: context.opsAccent,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selected!.displayName,
                    style: context.textStyles.h3.copyWith(
                      color: context.opsAccent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    selected!.isOrganization
                        ? '${selected!.contactName} · ${selected!.phone}'
                        : selected!.phone,
                    style: context.textStyles.caption,
                  ),
                  if (selected!.isOrganization) ...[
                    const SizedBox(height: 4),
                    const OrgBadge(),
                  ],
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
                  size: 16,
                  color: context.opsTextSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          decoration: _cardDecoration(context),
          child: TextField(
            key: const ValueKey('create_order_customer_search'),
            controller: ctrl,
            onChanged: onSearch,
            style: context.textStyles.body,
            decoration: InputDecoration(
              hintText: 'Нэр эсвэл утасны дугаараар хайх...',
              prefixIcon: Icon(
                Icons.search_rounded,
                color: context.opsTextHint,
                size: 20,
              ),
              suffixIcon: searching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: context.opsTextHint,
                      ),
                      onPressed: () {
                        ctrl.clear();
                        onSearch('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: context.opsSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                borderSide: BorderSide(color: context.opsAccent, width: 1.5),
              ),
            ),
          ),
        ),
        if (results.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: _cardDecoration(context),
            child: Column(
              children: [
                for (final (i, c) in results.take(6).indexed)
                  _PickRow(
                    icon: Icons.person_outline,
                    title: c.displayName,
                    subtitle: c.isOrganization
                        ? '${c.contactName} · ${c.phone}'
                        : c.phone,
                    isOrganization: c.isOrganization,
                    divider: i < results.take(6).length - 1,
                    onTap: () => onSelect(c),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        _AddButton(label: 'Шинэ харилцагч бүртгэх', onTap: onNewCustomer),
      ],
    );
  }
}

/// The customer taken from the picked vehicle. Read-only: the server takes
/// the order's customer to be the vehicle's owner; another customer means
/// another vehicle.
class _VehicleOwnerCard extends StatelessWidget {
  final CustomerSummary customer;

  const _VehicleOwnerCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('create_order_vehicle_owner'),
      width: double.infinity,
      decoration: _cardDecoration(context),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.opsAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppDimens.radiusMD),
            ),
            child: Icon(Icons.person_rounded, color: context.opsAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        customer.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.bodyMedium,
                      ),
                    ),
                    if (customer.isOrganization) ...[
                      const SizedBox(width: 6),
                      const OrgBadge(),
                    ],
                  ],
                ),
                Text(
                  customer.isOrganization
                      ? '${customer.contactName} · ${customer.phone}'
                      : customer.phone,
                  style: context.textStyles.caption,
                ),
                const SizedBox(height: 4),
                Text(
                  'Машины эзэмшигч — өөр харилцагч бол машинаа солино уу.',
                  style: context.textStyles.caption.copyWith(
                    color: context.opsTextHint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  // Customer search rows only; the picked customer has its own card.
  final bool selected = false;
  final bool divider;
  final bool isOrganization;
  final VoidCallback onTap;

  const _PickRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.divider,
    required this.onTap,
    this.isOrganization = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? context.opsAccent.withOpacity(0.06) : null,
          border: divider
              ? Border(bottom: BorderSide(color: context.opsDivider))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.opsAccent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppDimens.radiusSM),
              ),
              child: Icon(icon, color: context.opsAccent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.bodyMedium.copyWith(
                            color: selected ? context.opsAccent : null,
                          ),
                        ),
                      ),
                      if (isOrganization) ...[
                        const SizedBox(width: 6),
                        const OrgBadge(),
                      ],
                    ],
                  ),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, style: context.textStyles.caption),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.chevron_right,
              size: 18,
              color: selected ? context.opsAccent : context.opsTextHint,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final String label;
  final IconData icon;

  /// Null disables the button.
  final VoidCallback? onTap;
  const _AddButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.add_circle_outline,
  });

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? context.opsTextHint : context.opsAccent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: context.opsSurface,
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          border: Border.all(
            color: onTap == null
                ? context.opsDivider
                : context.opsAccent.withOpacity(0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Items section ─────────────────────────────────────────────────────────────

/// Staged lines and the two ways to add one: a catalog pick or hand entry.
/// Tapping a line reopens it; nothing reaches the server until the order is
/// created.
class _ItemsSection extends StatelessWidget {
  final List<OrderItemDraft> items;

  /// Hand entry needs `orders.itemPrice`.
  final bool canManual;
  final String? blockedHint;
  final VoidCallback onPickCatalog;
  final VoidCallback onAddManual;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onRemove;

  const _ItemsSection({
    required this.items,
    required this.canManual,
    required this.blockedHint,
    required this.onPickCatalog,
    required this.onAddManual,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (sum, i) => sum + i.total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isNotEmpty) ...[
          Container(
            key: const ValueKey('create_order_items'),
            clipBehavior: Clip.antiAlias,
            decoration: _cardDecoration(context),
            child: Column(
              children: [
                for (final (i, item) in items.indexed)
                  _DraftItemRow(
                    key: ValueKey('create_order_item_$i'),
                    item: item,
                    onTap: () => onEdit(i),
                    onRemove: () => onRemove(i),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Нийт (урьдчилсан)',
                          style: context.textStyles.caption,
                        ),
                      ),
                      Text(
                        formatMoneyNum(total),
                        key: const ValueKey('create_order_items_total'),
                        style: context.textStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: _AddButton(
                key: const ValueKey('create_order_item_catalog'),
                label: 'Сангаас сонгох',
                icon: Icons.manage_search_rounded,
                onTap: onPickCatalog,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _AddButton(
                key: const ValueKey('create_order_item_manual'),
                label: 'Гараар бүртгэх',
                icon: Icons.edit_note_rounded,
                onTap: canManual ? onAddManual : null,
              ),
            ),
          ],
        ),
        if (!canManual || blockedHint != null) ...[
          const SizedBox(height: 6),
          Text(
            blockedHint ??
                'Гараар үнэ оруулах эрх байхгүй — сангаас сонгоно уу.',
            style: context.textStyles.caption.copyWith(
              color: blockedHint != null
                  ? context.opsWarning
                  : context.opsTextHint,
            ),
          ),
        ],
      ],
    );
  }
}

class _DraftItemRow extends StatelessWidget {
  final OrderItemDraft item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _DraftItemRow({
    super.key,
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final kindColor = context.itemKindColor(item.kind);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.opsDivider)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: context.itemKindBackground(item.kind),
                borderRadius: BorderRadius.circular(AppDimens.radiusSM),
              ),
              child: Text(
                item.kind.label,
                style: context.textStyles.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: kindColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.bodyMedium,
                  ),
                  Text(
                    '${item.quantity.raw} × ${formatMoney(item.unitPrice.raw)}'
                    ' · ${item.fromCatalog ? 'Сангаас' : 'Гараар'}',
                    style: context.textStyles.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatMoneyNum(item.total),
              style: context.textStyles.captionMedium,
            ),
            IconButton(
              tooltip: 'Хасах',
              onPressed: onRemove,
              icon: Icon(Icons.close, size: 18, color: context.opsTextHint),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Branch section ────────────────────────────────────────────────────────────

class _BranchSection extends StatelessWidget {
  final List<BranchSummary> branches;
  final BranchSummary? selected;
  final ValueChanged<BranchSummary> onSelect;
  const _BranchSection({
    required this.branches,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    // Loading
    if (branches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.opsSurface,
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          border: Border.all(color: context.opsDivider),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Салбаруудыг ачааллаж байна...',
                style: context.textStyles.caption,
              ),
            ),
          ],
        ),
      );
    }

    // Single branch — show as a read-only selected card
    if (branches.length == 1) {
      final b = branches.first;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.opsSurface,
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          border: Border.all(color: context.opsGood.withOpacity(0.35)),
          boxShadow: [
            BoxShadow(
              color: context.opsGood.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: context.opsGood.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppDimens.radiusSM),
              ),
              child: Icon(
                Icons.storefront_rounded,
                color: context.opsGood,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.name, style: context.textStyles.bodyMedium),
                  if (b.address != null)
                    Text(b.address!, style: context.textStyles.caption),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: context.opsGood.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppDimens.radiusFull),
              ),
              child: Text(
                'Автомат',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: context.opsGood,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Multi-branch — radio list
    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(color: context.opsDivider),
        boxShadow: [
          BoxShadow(
            color: context.opsTextPrimary.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: branches.asMap().entries.map((entry) {
          final i = entry.key;
          final b = entry.value;
          final isSelected = b.id == selected?.id;

          return InkWell(
            onTap: () => onSelect(b),
            borderRadius: BorderRadius.vertical(
              top: i == 0
                  ? const Radius.circular(AppDimens.radiusMD)
                  : Radius.zero,
              bottom: i == branches.length - 1
                  ? const Radius.circular(AppDimens.radiusMD)
                  : Radius.zero,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? context.opsAccent.withOpacity(0.06)
                    : Colors.transparent,
                borderRadius: BorderRadius.vertical(
                  top: i == 0
                      ? const Radius.circular(AppDimens.radiusMD)
                      : Radius.zero,
                  bottom: i == branches.length - 1
                      ? const Radius.circular(AppDimens.radiusMD)
                      : Radius.zero,
                ),
                border: i < branches.length - 1
                    ? Border(bottom: BorderSide(color: context.opsDivider))
                    : null,
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? context.opsAccent
                          : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? context.opsAccent
                            : context.opsDivider,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            size: 12,
                            color: context.opsTextOnDark,
                          )
                        : null,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.name,
                          style: context.textStyles.bodyMedium.copyWith(
                            color: isSelected
                                ? context.opsAccent
                                : context.opsTextPrimary,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                        if (b.address != null)
                          Text(b.address!, style: context.textStyles.caption),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: context.opsAccent,
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Details section ───────────────────────────────────────────────────────────

// ─── Assignee ──────────────────────────────────────────────────────────────────

class _AssigneeSection extends StatelessWidget {
  final List<AssignableUser> users;
  final AssignableUser? selected;
  final bool loading;
  final String? error;
  final String? fieldError;
  final ValueChanged<AssignableUser> onChanged;
  final VoidCallback onRetry;
  const _AssigneeSection({
    required this.users,
    required this.selected,
    required this.loading,
    required this.error,
    this.fieldError,
    required this.onChanged,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (loading && users.isEmpty) {
      child = Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            'Мастеруудыг ачааллаж байна...',
            style: context.textStyles.caption,
          ),
        ],
      );
    } else if (error != null) {
      child = Row(
        children: [
          Expanded(
            child: Text(
              error!,
              style: context.textStyles.caption.copyWith(
                color: context.opsTextSecondary,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Дахин')),
        ],
      );
    } else {
      child = AppDropdown<String?>(
        key: const ValueKey('create_order_assignee_picker'),
        value: selected?.id,
        decoration: const InputDecoration(
          hintText: 'Мастер сонгоно уу',
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        items: [
          for (final u in users)
            AppDropdownItem<String?>(
              value: u.id,
              label: u.fullName.isEmpty ? '—' : u.fullName,
              leading: AssigneeAvatar(name: u.fullName, size: 28),
            ),
        ],
        onChanged: (id) {
          if (id == null) return;
          onChanged(users.firstWhere((u) => u.id == id));
        },
      );
    }
    final errText = fieldError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const ValueKey('create_order_assignee'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.opsSurface,
            borderRadius: BorderRadius.circular(AppDimens.radiusMD),
            border: Border.all(
              color: errText != null ? context.opsDanger : context.opsDivider,
            ),
          ),
          child: child,
        ),
        if (errText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              errText,
              style: context.textStyles.caption.copyWith(
                color: context.opsDanger,
              ),
            ),
          ),
      ],
    );
  }
}

class _DetailsSection extends StatelessWidget {
  final DateTime? scheduledAt;
  final TextEditingController notesCtrl;
  final DateFormat dateFmt;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;
  final int? estimatedDurationMinutes;
  final VoidCallback onPickDuration;
  final VoidCallback onClearDuration;
  const _DetailsSection({
    required this.scheduledAt,
    required this.notesCtrl,
    required this.dateFmt,
    required this.onPickDate,
    required this.onClearDate,
    required this.estimatedDurationMinutes,
    required this.onPickDuration,
    required this.onClearDuration,
  });

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
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Schedule row
          InkWell(
            onTap: onPickDate,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppDimens.radiusMD),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: scheduledAt != null
                          ? context.opsAccent.withOpacity(0.1)
                          : context.opsBackground,
                      borderRadius: BorderRadius.circular(AppDimens.radiusSM),
                    ),
                    child: Icon(
                      Icons.event_rounded,
                      size: 18,
                      color: scheduledAt != null
                          ? context.opsAccent
                          : context.opsTextHint,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Товлосон цаг',
                          style: context.textStyles.caption.copyWith(
                            color: scheduledAt != null
                                ? context.opsAccent
                                : context.opsTextSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          scheduledAt != null
                              ? dateFmt.format(scheduledAt!)
                              : 'Огноо, цаг сонгоно уу',
                          style: context.textStyles.body.copyWith(
                            color: scheduledAt != null
                                ? context.opsTextPrimary
                                : context.opsTextHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (scheduledAt != null)
                    GestureDetector(
                      onTap: onClearDate,
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: context.opsTextHint,
                      ),
                    )
                  else
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: context.opsTextHint,
                    ),
                ],
              ),
            ),
          ),

          const Divider(height: 1),

          // Estimated duration row
          InkWell(
            key: const ValueKey('create_order_duration_row'),
            onTap: onPickDuration,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: estimatedDurationMinutes != null
                          ? context.opsAccent.withOpacity(0.1)
                          : context.opsBackground,
                      borderRadius: BorderRadius.circular(AppDimens.radiusSM),
                    ),
                    child: Icon(
                      Icons.timer_outlined,
                      size: 18,
                      color: estimatedDurationMinutes != null
                          ? context.opsAccent
                          : context.opsTextHint,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ажлын хугацаа',
                          style: context.textStyles.caption.copyWith(
                            color: estimatedDurationMinutes != null
                                ? context.opsAccent
                                : context.opsTextSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          estimatedDurationMinutes != null
                              ? '$estimatedDurationMinutes мин'
                              : 'Хугацаа сонгоно уу',
                          style: context.textStyles.body.copyWith(
                            color: estimatedDurationMinutes != null
                                ? context.opsTextPrimary
                                : context.opsTextHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (estimatedDurationMinutes != null)
                    GestureDetector(
                      onTap: onClearDuration,
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: context.opsTextHint,
                      ),
                    )
                  else
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: context.opsTextHint,
                    ),
                ],
              ),
            ),
          ),

          const Divider(height: 1),

          // Notes
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: context.opsBackground,
                      borderRadius: BorderRadius.circular(AppDimens.radiusSM),
                    ),
                    child: Icon(
                      Icons.notes_rounded,
                      size: 18,
                      color: context.opsTextHint,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    style: context.textStyles.body,
                    decoration: const InputDecoration(
                      hintText: 'Тэмдэглэл... (заавал биш)',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sticky bottom bar ─────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final CustomerSummary? customer;
  final VehicleSummary? vehicle;
  final BranchSummary? branch;
  final DateTime? scheduledAt;
  final DateFormat dateFmt;
  final int itemCount;
  final String? blockedHint;
  final bool canSubmit;
  final bool submitting;
  final VoidCallback onSubmit;

  const _BottomBar({
    required this.customer,
    required this.vehicle,
    required this.branch,
    required this.scheduledAt,
    required this.dateFmt,
    required this.itemCount,
    required this.blockedHint,
    required this.canSubmit,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    // Determine what's missing
    // In the form's order: the vehicle (which brings its owner) first.
    final String? missingHint = vehicle == null
        ? 'Машин сонгоогүй байна'
        : customer == null
        ? 'Харилцагч сонгоогүй байна'
        : branch == null
        ? 'Салбар сонгоогүй байна'
        : blockedHint;

    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        border: Border(top: BorderSide(color: context.opsDivider)),
        boxShadow: [
          BoxShadow(
            color: context.opsTextPrimary.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Summary row when ready
          if (canSubmit) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.opsBackground,
                borderRadius: BorderRadius.circular(AppDimens.radiusSM),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.directions_car_outlined,
                    size: 13,
                    color: context.opsTextSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    plateLabel(vehicle!.plate, vehicle!.vin),
                    style: context.textStyles.captionMedium,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      '· ${vehicle!.displayName}',
                      style: context.textStyles.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (itemCount > 0) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.build_outlined,
                      size: 13,
                      color: context.opsTextSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$itemCount мөр',
                      key: const ValueKey('create_order_item_count'),
                      style: context.textStyles.caption,
                    ),
                  ],
                  if (scheduledAt != null) ...[
                    SizedBox(width: 6),
                    Icon(
                      Icons.event_outlined,
                      size: 13,
                      color: context.opsTextSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      dateFmt.format(scheduledAt!),
                      style: context.textStyles.caption,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Requirements hint when not ready
          if (missingHint != null) ...[
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: context.opsWarning,
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    missingHint,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.opsWarning,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: canSubmit
                ? Material(
                    borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: submitting
                            ? null
                            : LinearGradient(
                                colors: [
                                  context.opsAccent,
                                  context.opsAccent.withBlue(220),
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                        color: submitting
                            ? context.opsAccent.withOpacity(0.6)
                            : null,
                        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                        boxShadow: submitting
                            ? null
                            : [
                                BoxShadow(
                                  color: context.opsAccent.withOpacity(0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                      ),
                      child: InkWell(
                        onTap: submitting ? null : onSubmit,
                        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                        child: Center(
                          child: submitting
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
                                      Icons.add_circle_outline,
                                      size: 18,
                                      color: context.opsTextOnDark,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Засварын хуудас үүсгэх',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: context.opsTextOnDark,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: context.opsDivider,
                      borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                    ),
                    child: Center(
                      child: Text(
                        'Засварын хуудас үүсгэх',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.opsTextHint,
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
