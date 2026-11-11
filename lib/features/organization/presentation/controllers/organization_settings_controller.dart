import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/utils/async_value.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/organization/data/organization_repository.dart';
import 'package:carservice_business/features/organization/domain/organization.dart';
import 'package:carservice_business/features/organization/domain/organization_repository.dart';
import 'package:carservice_business/features/profile/data/me_repository.dart';

/// Outcome of [OrganizationSettingsController.save].
enum OrganizationSaveOutcome { saved, unchanged, failed }

/// "Байгууллагын тохиргоо" state: the loaded settings, the save in flight
/// and the server's field errors, plus the logo upload/remove.
class OrganizationSettingsController extends ChangeNotifier {
  OrganizationSettingsController({
    OrganizationRepository? repo,
    Future<void> Function()? refreshUser,
  }) : _repo = repo ?? RemoteOrganizationRepository(),
       _refreshUser = refreshUser ?? _refreshCachedUser;

  final OrganizationRepository _repo;

  /// The signed-in user caches the tenant name (headers, greeting); a
  /// rename refreshes it from `/me`.
  final Future<void> Function() _refreshUser;

  static Future<void> _refreshCachedUser() async {
    await MeRepository().refresh();
  }

  AsyncValue<OrganizationSettings> state = const AsyncLoading();
  bool saving = false;
  bool logoBusy = false;
  Map<String, String> fieldErrors = const {};
  String? formError;
  bool _disposed = false;

  OrganizationSettings? get settings => state.valueOrNull;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (state is! AsyncData) {
      state = const AsyncLoading();
      _notify();
    }
    final result = await _repo.load();
    state = switch (result) {
      Ok(:final value) => AsyncData(value),
      Err(:final error) => settings != null ? state : AsyncError(error),
    };
    _notify();
  }

  void clearFieldError(String field) {
    if (!fieldErrors.containsKey(field)) return;
    fieldErrors = Map.of(fieldErrors)..remove(field);
    _notify();
  }

  Future<OrganizationSaveOutcome> save(OrganizationDraft draft) async {
    final current = settings;
    if (current == null || saving) return OrganizationSaveOutcome.failed;
    final patch = draft.patchFrom(current);
    fieldErrors = const {};
    formError = null;
    if (patch.isEmpty) {
      _notify();
      return OrganizationSaveOutcome.unchanged;
    }
    saving = true;
    _notify();
    final result = await _repo.update(patch);
    saving = false;
    switch (result) {
      case Ok(:final value):
        state = AsyncData(value);
        _notify();
        if (patch.containsKey('name')) unawaited(_refreshUser().catchError((_) {}));
        return OrganizationSaveOutcome.saved;
      case Err(:final error):
        _applyError(error);
        _notify();
        return OrganizationSaveOutcome.failed;
    }
  }

  void _applyError(AppError error) {
    final fe = error.fieldErrors ?? const <String, String>{};
    fieldErrors = fe;
    // Errors on a field the form shows stay inline; anything else (403,
    // network, a field this form has no input for) is the form's error.
    const shown = {
      'name',
      'registerNumber',
      'email',
      'phone1',
      'phone2',
      'acceptsOnlineBooking',
      'appointmentReminderLeadMinutes',
    };
    formError = fe.keys.any(shown.contains) ? null : error.display;
  }

  /// Answers an error message, or null on success.
  Future<String?> uploadLogo(String path) async {
    final current = settings;
    if (current == null || logoBusy) return null;
    logoBusy = true;
    _notify();
    final result = await _repo.uploadLogo(path);
    logoBusy = false;
    String? message;
    switch (result) {
      case Ok(:final value):
        state = AsyncData((settings ?? current).copyWith(logoUrl: value));
      case Err(:final error):
        message = error.fieldErrors?['file'] ?? error.display;
    }
    _notify();
    return message;
  }

  Future<String?> removeLogo() async {
    final current = settings;
    if (current == null || logoBusy) return null;
    logoBusy = true;
    _notify();
    final result = await _repo.removeLogo();
    logoBusy = false;
    String? message;
    switch (result) {
      case Ok():
        state = AsyncData((settings ?? current).copyWith(clearLogo: true));
      case Err(:final error):
        message = error.display;
    }
    _notify();
    return message;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
