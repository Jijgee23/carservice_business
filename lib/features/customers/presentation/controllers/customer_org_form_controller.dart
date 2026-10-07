import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/utils/validators.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';
import 'package:carservice_business/features/customers/domain/customers_repository.dart';

/// Form state for the "Байгууллага" section shared by the new-customer sheet
/// and the customer edit sheet (Phase 4).
///
/// Owns the three org text controllers, the toggle, and the debounced
/// `GET /ebarimt/org` lookup. The lookup is advisory: it autofills the org
/// name when that is empty or still the previous autofill, surfaces a quiet
/// inline [lookupError] on failure, and never blocks saving.
class CustomerOrgFormController extends ChangeNotifier {
  CustomerOrgFormController({
    required CustomersRepository repository,
    Customer? initial,
    this.debounce = const Duration(milliseconds: 500),
  }) : _repo = repository,
       _isOrganization = initial?.isOrganization ?? false,
       regnumCtrl = TextEditingController(text: initial?.orgRegnum ?? ''),
       nameCtrl = TextEditingController(text: initial?.orgName ?? ''),
       emailCtrl = TextEditingController(text: initial?.orgEmail ?? '') {
    _lastRegnum = regnumCtrl.text.trim();
    regnumCtrl.addListener(_onRegnumChanged);
  }

  final CustomersRepository _repo;
  final Duration debounce;

  final TextEditingController regnumCtrl;
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;

  bool _isOrganization;
  bool _disposed = false;
  Timer? _timer;
  int _generation = 0;
  String _lastRegnum = '';

  /// The org name most recently written by a lookup — an edit by the user
  /// makes [nameCtrl] differ from it, which stops later lookups overwriting.
  String? _lastAutofill;

  bool lookingUp = false;

  /// Quiet inline message for a failed lookup; null otherwise.
  String? lookupError;

  bool get isOrganization => _isOrganization;

  /// Switching off clears every org field (the server nulls them too).
  void setOrganization(bool value) {
    if (value == _isOrganization) return;
    _isOrganization = value;
    if (!value) {
      _timer?.cancel();
      _generation++;
      regnumCtrl.removeListener(_onRegnumChanged);
      regnumCtrl.clear();
      regnumCtrl.addListener(_onRegnumChanged);
      nameCtrl.clear();
      emailCtrl.clear();
      _lastRegnum = '';
      _lastAutofill = null;
      lookingUp = false;
      lookupError = null;
    }
    notifyListeners();
  }

  // ── Validators (only meaningful when [isOrganization]) ────────────────────

  String? validateRegnum(String? v) =>
      _isOrganization ? AppValidators.orgRegnum(v) : null;

  String? validateName(String? v) =>
      _isOrganization ? AppValidators.required(v, 'Байгууллагын нэр') : null;

  String? validateEmail(String? v) =>
      _isOrganization ? AppValidators.optionalEmail(v) : null;

  // ── Values for create / update ────────────────────────────────────────────

  String? get orgRegnum => _isOrganization ? regnumCtrl.text.trim() : null;
  String? get orgName => _isOrganization ? nameCtrl.text.trim() : null;
  String? get orgEmail {
    if (!_isOrganization) return null;
    final v = emailCtrl.text.trim();
    return v.isEmpty ? null : v;
  }

  // ── Lookup ────────────────────────────────────────────────────────────────

  void _onRegnumChanged() {
    final value = regnumCtrl.text.trim();
    if (value == _lastRegnum) return;
    _lastRegnum = value;
    _timer?.cancel();
    _generation++;
    final hadState = lookingUp || lookupError != null;
    lookingUp = false;
    lookupError = null;
    if (hadState) notifyListeners();
    if (!_isOrganization || !AppValidators.isValidOrgRegnum(value)) return;
    _timer = Timer(debounce, () => lookup(value));
  }

  /// Runs the lookup for [regno] now (the debounce path calls this).
  Future<void> lookup(String regno) async {
    if (_disposed) return;
    final generation = ++_generation;
    lookingUp = true;
    lookupError = null;
    notifyListeners();
    final result = await _repo.lookupOrg(regno);
    // Stale: regnum changed, org switched off, or disposed meanwhile.
    if (_disposed || generation != _generation) return;
    lookingUp = false;
    switch (result) {
      case Ok(:final value):
        final current = nameCtrl.text.trim();
        if (current.isEmpty || current == _lastAutofill) {
          nameCtrl.text = value.name;
          _lastAutofill = value.name;
        }
      case Err(:final error):
        lookupError = switch (error.code) {
          OrgLookupErrorCode.notFound =>
            'Байгууллага олдсонгүй. Нэрийг гараар оруулна уу.',
          OrgLookupErrorCode.regnoInvalid => null,
          _ => 'Лавлагаа хийж чадсангүй. Нэрийг гараар оруулна уу.',
        };
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    regnumCtrl.dispose();
    nameCtrl.dispose();
    emailCtrl.dispose();
    super.dispose();
  }
}
