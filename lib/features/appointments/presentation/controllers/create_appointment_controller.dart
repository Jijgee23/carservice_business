import 'package:carservice_business/core/utils/business_time.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/services/diagnostic_service.dart';
import 'package:carservice_business/core/services/service_catalog_service.dart';
import 'package:carservice_business/core/domain/service_catalog.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/appointments/domain/appointment.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/features/appointments/data/appointment_repository.dart';
import 'package:carservice_business/features/appointments/domain/appointments_repository.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/features/appointments/domain/appointment_error_codes.dart';
import 'package:carservice_business/features/appointments/domain/assignee_access.dart';
import 'package:carservice_business/features/orders/data/order_repository.dart';
import 'package:carservice_business/features/orders/domain/order.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';

class CreateAppointmentController extends ChangeNotifier {
  CreateAppointmentController({
    AppointmentsRepository? repo,
    DateTime? initialDate,
    this.workingBranchId,
    OrdersRepository? ordersRepo,
    bool? canAssign,
    String? currentUserId,
  }) : _repo = repo ?? RemoteAppointmentsRepository(),
       canAssign = canAssign ?? currentUserCanAssign(),
       _currentUserId = currentUserId ?? currentUserIdOrNull() {
    _ordersRepo = ordersRepo;
    if (initialDate != null) {
      selectedDate = DateTime(
        initialDate.year,
        initialDate.month,
        initialDate.day,
      );
    }
  }

  final AppointmentsRepository _repo;
  OrdersRepository? _ordersRepo;
  OrdersRepository get _orders => _ordersRepo ??= RemoteOrdersRepository();
  final String? _currentUserId;

  // ─── Хариуцах мастер ───────────────────────────────────────────────────────
  // Mirrors `create_order_screen.dart`: `orders.assign` holders must pick a
  // master (branch-scoped list, current user preselected); everyone else gets
  // no picker and the server assigns the actor.

  /// Whether the signed-in user holds `orders.assign` (or is the owner).
  final bool canAssign;
  List<AssignableUser> assignees = [];
  bool loadingAssignees = false;
  String? assigneesError;
  AssignableUser? assignee;
  int _assigneesSeq = 0;

  /// Inline reason shown to a user without `orders.assign` whose create was
  /// refused with `ASSIGNEE_REQUIRED` (they are not an eligible master).
  String? assigneeBlockedReason;

  /// Concrete working branch from the shell (null = all branches).
  final String? workingBranchId;

  // ─── Form state ────────────────────────────────────────────────────────────

  DateTime selectedDate = _defaultDate();
  BranchSummary? selectedBranch;
  CustomerSummary? selectedCustomer;
  VehicleSummary? selectedVehicle;
  bool submitting = false;

  /// `422` field errors from the last failed submit, keyed by server field
  /// name (`branchId`, `customerId`, `requestedAt`, `categoryIds`, `note`).
  /// Bound directly onto the relevant field UI rather than flattened into a
  /// generic toast — never both.
  Map<String, String>? fieldErrors;
  String? fieldError(String key) => fieldErrors?[key];

  // ─── Branch ────────────────────────────────────────────────────────────────

  List<BranchSummary> branches = [];
  bool loadingBranches = true;

  // ─── Categories ────────────────────────────────────────────────────────────

  List<LaborCategory> categories = [];
  bool loadingCategories = true;
  final Set<String> selectedCategoryIds = <String>{};

  // ─── Slots ─────────────────────────────────────────────────────────────────

  AppointmentDayAvailability? availability;
  bool loadingSlots = false;
  AppError? slotsError;
  AppointmentSlot? selectedSlot;

  /// The server is the sole authority on capacity — this only mirrors the
  /// same past-vs-future-empty-capacity rule already implemented for the
  /// calendar in `calendar_grid_layout.dart`/`calendar_slot_cell.dart`
  /// (`isFuture && withinCapacity`), applied to `GET /appointments/slots`
  /// rows instead of calendar lanes. It never computes availability itself.
  bool isSlotBookable(AppointmentSlot slot) {
    final dt = DateTime.tryParse(slot.iso);
    if (dt == null) return false;
    return dt.isAfter(DateTime.now()) && slot.available;
  }

  // ─── Customer search ───────────────────────────────────────────────────────

  List<CustomerSummary> customerResults = [];
  bool searchingCustomer = false;
  Timer? _customerTimer;
  int _customerSearchGeneration = 0;

  // ─── Vehicle search ────────────────────────────────────────────────────────

  List<VehicleSummary> vehicleResults = [];
  bool searchingVehicle = false;
  Timer? _vehicleTimer;
  int _vehicleSearchGeneration = 0;

  /// The selected customer's own vehicles — shown as picks under the vehicle
  /// search (web order-form pattern) and auto-selected when there is one.
  List<VehicleSummary> customerVehicles = [];
  bool loadingCustomerVehicles = false;
  int _customerVehiclesGeneration = 0;

  // ─── Text controllers ──────────────────────────────────────────────────────

  final customerSearchCtrl = TextEditingController();
  final vehicleSearchCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  int _slotRequestGeneration = 0;
  bool _disposed = false;

  // ─── Computed ──────────────────────────────────────────────────────────────

  /// Mirrors exactly what `submit()`/`createAppointment` requires — a
  /// branch, a customer and a bookable selected slot. Keep this in lockstep
  /// with `submit()`'s precondition; a button that enables and then fails is
  /// the P2-F4a regression class.
  bool get canSubmit =>
      !submitting &&
      selectedBranch != null &&
      selectedCustomer != null &&
      selectedSlot != null &&
      isSlotBookable(selectedSlot!) &&
      (!canAssign || assignee != null);

  DateTime? get requestedAt {
    final slot = selectedSlot;
    if (slot == null) return null;
    return parseBusinessTime(slot.iso);
  }

  // ─── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    final list = await DiagnosticService.getBranches();
    if (_disposed) return;
    branches = list;
    // The shell's working branch first: slots/create are scoped by the
    // `X-Working-Branch` header, and a different branch here is a 422.
    final branchId = workingBranchId ?? Authenticator.user?.branchId;
    if (branchId != null) {
      try {
        selectedBranch = list.firstWhere((b) => b.id == branchId);
      } catch (_) {
        selectedBranch = list.isNotEmpty ? list.first : null;
      }
    } else if (list.isNotEmpty) {
      selectedBranch = list.first;
    }
    loadingBranches = false;
    notifyListeners();

    unawaited(_loadCategories());
    unawaited(loadAssignees());
    await _fetchSlots();
  }

  /// Loads the branch-scoped list of eligible masters (same endpoint as the
  /// order create screen) and preselects the current user when listed.
  Future<void> loadAssignees() async {
    final branch = selectedBranch;
    if (!canAssign || branch == null) return;
    final seq = ++_assigneesSeq;
    loadingAssignees = true;
    assigneesError = null;
    if (!_disposed) notifyListeners();
    final result = await _orders.getAssignableUsers(branchId: branch.id);
    if (_disposed || seq != _assigneesSeq) return;
    loadingAssignees = false;
    switch (result) {
      case Ok(:final value):
        assignees = value;
        final keep = assignee;
        if (keep != null && !value.any((u) => u.id == keep.id)) {
          assignee = null;
        }
        if (assignee == null) {
          for (final u in value) {
            if (u.id == _currentUserId) {
              assignee = u;
              break;
            }
          }
        }
      case Err(:final error):
        assignees = [];
        assignee = null;
        assigneesError = error.display;
    }
    notifyListeners();
  }

  void selectAssignee(AssignableUser user) {
    assignee = user;
    fieldErrors = fieldErrors == null
        ? null
        : (Map<String, String>.of(fieldErrors!)..remove('assignedToId'));
    notifyListeners();
  }

  Future<void> _loadCategories() async {
    final result = await ServiceCatalogService.getLaborCategories();
    if (_disposed) return;
    switch (result) {
      case Ok(:final value):
        categories = value.where((c) => c.isActive).toList();
      case Err():
        // Non-fatal — booking without a category stays valid; the server
        // is still the authority on whether a category is required.
        categories = [];
    }
    loadingCategories = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _slotRequestGeneration++;
    _customerSearchGeneration++;
    _vehicleSearchGeneration++;
    _customerTimer?.cancel();
    _vehicleTimer?.cancel();
    customerSearchCtrl.dispose();
    vehicleSearchCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  // ─── Date ──────────────────────────────────────────────────────────────────

  Future<void> setDate(DateTime date) async {
    selectedDate = DateTime(date.year, date.month, date.day);
    selectedSlot = null;
    fieldErrors = null;
    notifyListeners();
    await _fetchSlots();
  }

  // ─── Branch ────────────────────────────────────────────────────────────────

  Future<void> selectBranch(BranchSummary b) async {
    if (selectedBranch?.id == b.id) return;
    selectedBranch = b;
    selectedSlot = null;
    fieldErrors = null;
    notifyListeners();
    unawaited(loadAssignees());
    await _fetchSlots();
  }

  // ─── Categories ────────────────────────────────────────────────────────────

  Future<void> toggleCategory(String categoryId) async {
    if (!selectedCategoryIds.remove(categoryId)) {
      selectedCategoryIds.add(categoryId);
    }
    selectedSlot = null;
    fieldErrors = null;
    notifyListeners();
    await _fetchSlots();
  }

  // ─── Slots ─────────────────────────────────────────────────────────────────

  Future<void> _fetchSlots() async {
    final requestGeneration = ++_slotRequestGeneration;
    final branchId = selectedBranch?.id;
    final date = selectedDate;
    final categoryIds = selectedCategoryIds.toList(growable: false);
    if (branchId == null) {
      availability = null;
      slotsError = null;
      if (!_disposed) notifyListeners();
      return;
    }
    loadingSlots = true;
    slotsError = null;
    if (!_disposed) notifyListeners();

    final result = await _repo.getSlots(
      branchId: branchId,
      date: date,
      categoryIds: categoryIds,
    );
    if (_disposed || requestGeneration != _slotRequestGeneration) return;

    switch (result) {
      case Ok(:final value):
        availability = value;
        final current = selectedSlot;
        if (current != null) {
          AppointmentSlot? refreshed;
          for (final s in value.slots) {
            if (s.iso == current.iso) {
              refreshed = s;
              break;
            }
          }
          selectedSlot = (refreshed != null && isSlotBookable(refreshed))
              ? refreshed
              : null;
        }
      case Err(:final error):
        availability = null;
        slotsError = error;
        selectedSlot = null;
    }

    loadingSlots = false;
    notifyListeners();
  }

  void selectSlot(AppointmentSlot slot) {
    if (!isSlotBookable(slot)) return;
    selectedSlot = slot;
    fieldErrors = null;
    notifyListeners();
  }

  // ─── Customer ──────────────────────────────────────────────────────────────

  void searchCustomer(String q) {
    final generation = ++_customerSearchGeneration;
    _customerTimer?.cancel();
    if (q.trim().isEmpty) {
      customerResults = [];
      if (!_disposed) notifyListeners();
      return;
    }
    _customerTimer = Timer(const Duration(milliseconds: 400), () async {
      if (_disposed || generation != _customerSearchGeneration) return;
      searchingCustomer = true;
      notifyListeners();
      final results = await DiagnosticService.searchCustomers(q.trim());
      if (_disposed || generation != _customerSearchGeneration) return;
      customerResults = results;
      searchingCustomer = false;
      notifyListeners();
    });
  }

  void selectCustomer(CustomerSummary c) {
    selectedCustomer = c;
    customerResults = [];
    customerSearchCtrl.clear();
    fieldErrors = null;
    final v = selectedVehicle;
    final owner = v?.customerId ?? v?.customer?.id;
    if (v != null && owner != null && owner != c.id) selectedVehicle = null;
    notifyListeners();
    _loadCustomerVehicles(c.id);
  }

  Future<void> _loadCustomerVehicles(String customerId) async {
    final generation = ++_customerVehiclesGeneration;
    customerVehicles = [];
    loadingCustomerVehicles = true;
    if (!_disposed) notifyListeners();
    final list = await DiagnosticService.vehiclesForCustomer(customerId);
    if (_disposed || generation != _customerVehiclesGeneration) return;
    customerVehicles = list;
    loadingCustomerVehicles = false;
    if (selectedVehicle == null) {
      if (list.length == 1) {
        selectedVehicle = list.first;
      } else if (vehicleSearchCtrl.text.trim().isEmpty) {
        vehicleResults = list;
      }
    }
    notifyListeners();
  }

  void clearCustomer() {
    selectedCustomer = null;
    selectedVehicle = null;
    vehicleResults = [];
    customerVehicles = [];
    loadingCustomerVehicles = false;
    _customerVehiclesGeneration++;
    customerSearchCtrl.clear();
    vehicleSearchCtrl.clear();
    notifyListeners();
  }

  // ─── Vehicle ───────────────────────────────────────────────────────────────

  void searchVehicle(String q) {
    final generation = ++_vehicleSearchGeneration;
    _vehicleTimer?.cancel();
    if (q.trim().isEmpty) {
      // Empty query falls back to the selected customer's own vehicles.
      vehicleResults = customerVehicles;
      if (!_disposed) notifyListeners();
      return;
    }
    _vehicleTimer = Timer(const Duration(milliseconds: 400), () async {
      if (_disposed || generation != _vehicleSearchGeneration) return;
      searchingVehicle = true;
      notifyListeners();
      final results = await DiagnosticService.searchVehicles(q.trim());
      if (_disposed || generation != _vehicleSearchGeneration) return;
      vehicleResults = results;
      searchingVehicle = false;
      notifyListeners();
    });
  }

  void selectVehicle(VehicleSummary v) {
    selectedVehicle = v;
    vehicleResults = [];
    vehicleSearchCtrl.clear();
    if (selectedCustomer == null && v.customer != null) {
      selectedCustomer = v.customer;
    }
    notifyListeners();
  }

  void clearVehicle() {
    selectedVehicle = null;
    vehicleSearchCtrl.clear();
    vehicleResults = customerVehicles;
    notifyListeners();
  }

  // ─── Submit ────────────────────────────────────────────────────────────────

  Future<AppointmentSummary?> submit() async {
    // Double-submit guard: `canSubmit` already folds in `!submitting`, and
    // this re-checks it so a stray programmatic call cannot race the guard.
    if (!canSubmit) return null;
    final slot = selectedSlot!;
    // Business wall-clock (UTC+8), not the device zone: the server reads the
    // zone-less `requestedAt` as +08:00.
    final requestedAtValue = parseBusinessTime(slot.iso);
    if (requestedAtValue == null) return null;

    final customerId = selectedCustomer!.id;
    submitting = true;
    fieldErrors = null;
    assigneeBlockedReason = null;
    notifyListeners();

    final result = await _repo.createAppointment(
      branchId: selectedBranch!.id,
      customerId: customerId,
      vehicleId: selectedVehicle?.id,
      requestedAt: requestedAtValue,
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      categoryIds: selectedCategoryIds.toList(),
      assignedToId: canAssign ? assignee!.id : null,
    );

    submitting = false;
    if (_disposed) return null;

    switch (result) {
      case Ok(:final value):
        notifyListeners();
        return value;
      case Err(:final error):
        if (error.statusCode == 409) {
          // Slot conflict — the server is the sole authority on capacity.
          // Never retry the submit automatically and never invent local
          // availability; re-fetch the real slots and tell the user.
          selectedSlot = null;
          notifyListeners();
          await _fetchSlots();
          messageWarning(
            'Сонгосон цаг аль хэдийн авагдсан байна. Цагийн жагсаалтыг '
            'шинэчиллээ, шинээр сонгоно уу.',
          );
        } else if (error.code == AppointmentErrorCodes.assigneeRequired &&
            !canAssign) {
          // No picker for this user: explain inline why they cannot book.
          assigneeBlockedReason = kAssigneeNoPermissionReason;
          notifyListeners();
        } else if (error.fieldErrors != null && error.fieldErrors!.isNotEmpty) {
          fieldErrors = error.fieldErrors;
          notifyListeners();
        } else {
          notifyListeners();
          messageError(error.display);
        }
        return null;
    }
  }

  static DateTime _defaultDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}
