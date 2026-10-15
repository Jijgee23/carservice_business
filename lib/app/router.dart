import 'package:carservice_business/app/shell/shell_chrome.dart';

import 'dart:async';

import 'package:carservice_business/app/shell/app_shell.dart';
import 'package:carservice_business/core/keys/keys.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/core/services/subscription_service.dart';
import 'package:carservice_business/features/appointments/presentation/screens/appointment_detail_route.dart';
import 'package:carservice_business/features/appointments/presentation/screens/appointment_screen.dart';
import 'package:carservice_business/features/auth/presentation/screens/login_screen.dart';
import 'package:carservice_business/features/controllers.dart';
import 'package:carservice_business/features/customers/presentation/screens/customer_detail_screen.dart';
import 'package:carservice_business/features/customers/presentation/screens/customer_search_tab.dart';
import 'package:carservice_business/features/vehicles/domain/vehicle.dart';
import 'package:carservice_business/features/vehicles/presentation/screens/vehicle_detail_screen.dart';
import 'package:carservice_business/features/vehicles/presentation/screens/vehicle_create_screen.dart';
import 'package:carservice_business/features/vehicles/presentation/screens/vehicle_list_screen.dart';
import 'package:carservice_business/features/orders/domain/orders_repository.dart';
import 'package:carservice_business/features/orders/presentation/controllers/order_detail_controller.dart';
import 'package:carservice_business/features/orders/presentation/screens/in_progress_screen.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_detail_screen.dart';
import 'package:carservice_business/features/orders/presentation/screens/order_list_screen.dart';
import 'package:carservice_business/features/orders/presentation/screens/postpaid_screen.dart';
import 'package:carservice_business/features/overview/presentation/screens/home_screen.dart';
import 'package:carservice_business/features/profile/presentation/screens/account_closure_screen.dart';
import 'package:carservice_business/features/profile/presentation/screens/change_password_screen.dart';
import 'package:carservice_business/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:carservice_business/features/profile/presentation/screens/profile_screen.dart';
import 'package:carservice_business/features/profile/presentation/screens/sessions_screen.dart';
import 'package:carservice_business/features/reports/presentation/screens/reports_screen.dart';
import 'package:carservice_business/features/audit/presentation/screens/audit_list_screen.dart';
import 'package:carservice_business/features/feedback/domain/feedback.dart'
    as feedback_domain;
import 'package:carservice_business/features/feedback/presentation/screens/feedback_create_screen.dart';
import 'package:carservice_business/features/feedback/presentation/screens/feedback_detail_screen.dart';
import 'package:carservice_business/features/feedback/presentation/screens/feedback_list_screen.dart';
import 'package:carservice_business/features/notifications/presentation/screens/notification_screen.dart';
import 'package:carservice_business/features/settings/presentation/screens/about_screen.dart';
import 'package:carservice_business/features/settings/presentation/screens/privacy_policy_screen.dart';
import 'package:carservice_business/features/settings/presentation/screens/terms_of_service_screen.dart';
import 'package:carservice_business/features/auth/presentation/screens/terms_consent_screen.dart';
import 'package:carservice_business/core/services/legal_consent_store.dart';
import 'package:carservice_business/features/settings/presentation/screens/help_screen.dart';
import 'package:carservice_business/features/services/domain/service.dart';
import 'package:carservice_business/features/services/presentation/screens/create_service_screen.dart';
import 'package:carservice_business/features/services/presentation/screens/service_detail_screen.dart';
import 'package:carservice_business/features/services/presentation/screens/service_list_screen.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/report_list_screen.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/template_list_screen.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/new_inspection_screen.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/create_template_screen.dart';
import 'package:carservice_business/features/diagnostics/presentation/screens/report_detail_screen.dart';
import 'package:carservice_business/features/shell/presentation/screens/search_screen.dart';
import 'package:carservice_business/features/today/presentation/screens/today_screen.dart';
import 'package:carservice_business/features/shell/presentation/controllers/working_branch_controller.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/employees/data/employee_repository.dart';
import 'package:carservice_business/features/employees/domain/employee.dart';
import 'package:carservice_business/features/employees/domain/employees_repository.dart';
import 'package:carservice_business/features/employees/presentation/screens/employee_bulk_screen.dart';
import 'package:carservice_business/features/employees/presentation/screens/employee_detail_screen.dart';
import 'package:carservice_business/features/employees/presentation/screens/employee_form_screen.dart';
import 'package:carservice_business/features/employees/presentation/screens/employee_list_screen.dart';
import 'package:carservice_business/features/roles/data/role_repository.dart';
import 'package:carservice_business/features/roles/domain/role.dart';
import 'package:carservice_business/features/roles/domain/roles_repository.dart';
import 'package:carservice_business/features/roles/presentation/screens/role_form_screen.dart';
import 'package:carservice_business/features/roles/presentation/screens/role_list_screen.dart';
import 'package:carservice_business/features/schedules/presentation/screens/my_schedule_screen.dart';
import 'package:carservice_business/features/schedules/presentation/screens/schedule_grid_screen.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class AppRoutes {
  AppRoutes._();

  static const splash = '/splash';
  static const login = '/login';
  static const locked = '/locked';

  /// Accept the terms — every signed-in user who has not, yet (see
  /// [LegalConsentStore]).
  static const consent = '/consent';
  static const overview = '/overview';
  static const orders = '/orders';
  static const ordersInProgress = '/orders/in-progress';
  static const ordersPostpaid = '/orders/postpaid';
  static const appointments = '/appointments';
  static const search = '/search';
  static const more = '/more';
  static const customers = '/customers';
  static const vehicles = '/vehicles';
  static const services = '/services';
  static const diagnosticsReports = '/diagnostics/reports';
  static const diagnosticsTemplates = '/diagnostics/templates';
  static const employees = '/employees';
  static const roles = '/roles';
  static const schedules = '/schedules';
  static const mySchedule = '/my-schedule';
  static const reports = '/reports';
  static const audit = '/audit';
  static const feedback = '/feedback';
  static const profileEdit = '/profile/edit';
  static const profilePassword = '/profile/password';
  static const profileSessions = '/profile/sessions';
  static const profileClosure = '/profile/closure';
}

/// Pages opened by name with [AppNav.toNamed], GetX-style: full-screen above
/// the tabs, no URL, the arguments go straight to the page —
/// `AppNav.toNamed(AppPages.orderDetail, arguments: order.id)`. Builders
/// run outside the shell, so they see the app-level providers only.
///
/// [AppRoutes] stay for URLs: deep links, notifications, the tabs.
abstract final class AppPages {
  /// Arguments: the order id.
  static const orderDetail = '/order-detail';

  // The Бусад tab's profile card and Ерөнхий rows; no arguments.
  static const profile = '/profile';
  static const notifications = '/notifications';
  static const feedback = '/feedback';
  static const help = '/help';
  static const about = '/about';

  /// Also opened from the login page, before sign-in.
  static const privacy = '/privacy';
  static const terms = '/terms';

  static final Map<String, AppPageBuilder> all = {
    orderDetail: (context, arguments) => switch (arguments) {
      final String id when id.isNotEmpty => _orderDetail(context, id),
      _ => const _MissingOrderRoute(),
    },
    profile: (_, _) => const ProfileScreen(),
    notifications: (_, _) => const NotificationScreen(),
    feedback: (_, _) => _FeedbackListRoute(),
    help: (_, _) => const HelpScreen(),
    about: (_, _) => const AboutScreen(),
    privacy: (_, _) => const PrivacyPolicyScreen(),
    terms: (_, _) => const TermsOfServiceScreen(),
  };
}

GoRouter buildRouter(AuthController authController) {
  final router = GoRouter(
    navigatorKey: GlobalKeys.navigator,
    initialLocation: AppRoutes.splash,
    // Consent too: accepting the terms moves the user on.
    refreshListenable: Listenable.merge([
      authController,
      LegalConsentStore.instance,
    ]),
    redirect: (context, state) => _redirect(context, state, authController),
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const _SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.locked,
        builder: (_, _) => const SubscriptionLockedScreen(),
      ),
      GoRoute(
        path: AppRoutes.consent,
        builder: (_, _) => const TermsConsentScreen(),
      ),

      // ── Customers / Vehicles — first real GoRoutes, P3-F6 ──────────────
      //
      // These are top-level routes (outside the `StatefulShellRoute`,
      // exactly like `/login`/`/locked`) rather than nested under a tab
      // branch: neither Customers nor Vehicles is a bottom-nav destination
      // today, so a deep link or an in-app push lands as a full screen above
      // the shell, matching how `NotificationScreen`/`ProfileScreen` are
      // already pushed. `CustomerDetailScreen` / `VehicleDetailScreen`
      // (P3-F4/P3-F5) are constructed with only an id — the same contract a
      // cold deep-link start requires — and default their own repository
      // when none is injected, so no repo needs threading through here.
      GoRoute(
        path: AppRoutes.customers,
        builder: (_, _) => const _CustomerListRoute(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || id.isEmpty) {
                return const _MissingCustomerRoute();
              }
              return CustomerDetailScreen(customerId: id);
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.vehicles,
        builder: (_, _) => const _VehicleListRoute(),
        routes: [
          // Literal before `:id` so `/vehicles/new` is not read as an id.
          GoRoute(path: 'new', builder: (_, _) => const VehicleCreateScreen()),
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || id.isEmpty) {
                return const _MissingVehicleRoute();
              }
              return VehicleDetailScreen(vehicleId: id);
            },
          ),
        ],
      ),

      // ── Services — first real GoRoutes, P4-F4 ──────────────────────────
      //
      // Same top-level shape as Customers/Vehicles above: Services is not a
      // bottom-nav destination, so it lands as a full screen above the
      // shell. `ServiceListScreen` (P4-F2) and `ServiceDetailScreen`
      // (P4-F3) already expose `onSelectService`/`onCreateService` hooks and
      // an id-only constructor precisely so this slice could wire them
      // without touching either screen's owning slice — see
      // `service_list_screen.dart`'s doc comment. `'new'` is registered
      // ahead of `':id'`, matching `orders`'s `in-progress`/`postpaid`
      // literal-before-parameter convention, so a literal path segment is
      // never swallowed by the dynamic one.
      //
      // Editing an existing service does **not** get its own route:
      // `ServiceDetailScreen._edit` already pushes `CreateServiceScreen(
      // existing: service)` imperatively and reloads on a truthy pop, the
      // same self-contained shape Customers/Vehicles use for their own
      // in-screen navigation (`CustomerSearchTab`'s note in
      // `_CustomerListRoute`'s doc comment) — there is no
      // customer/vehicle edit route to mirror because neither needed one.
      GoRoute(
        path: AppRoutes.services,
        builder: (context, state) => _ServiceListRoute(
          initialType: _parseServiceKindParam(
            state.uri.queryParameters['type'],
          ),
        ),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => CreateServiceScreen(
              initialType:
                  _parseServiceKindParam(state.uri.queryParameters['type']) ??
                  ServiceKind.labor,
            ),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || id.isEmpty) {
                return const _MissingServiceRoute();
              }
              return ServiceDetailScreen(serviceId: id);
            },
          ),
        ],
      ),

      // Keep literal paths before dynamic ids. These are siblings so a cold
      // deep link to create/detail does not instantiate (and fetch) the list.
      GoRoute(
        path: '${AppRoutes.diagnosticsReports}/new',
        builder: (_, _) => const NewInspectionScreen(),
      ),
      GoRoute(
        path: AppRoutes.diagnosticsReports,
        builder: (_, _) => const ReportListScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.diagnosticsReports}/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'];
          return id == null || id.isEmpty
              ? const _MissingDiagnosticRoute()
              : ReportDetailScreen(reportId: id);
        },
      ),
      GoRoute(
        path: '${AppRoutes.diagnosticsTemplates}/new',
        builder: (_, _) => const CreateTemplateScreen(),
      ),
      GoRoute(
        path: AppRoutes.diagnosticsTemplates,
        builder: (_, _) => const TemplateListScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.diagnosticsTemplates}/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'];
          return id == null || id.isEmpty
              ? const _MissingDiagnosticRoute()
              : CreateTemplateScreen(templateId: id);
        },
      ),

      // ── Хүмүүс (Employees/Roles/Schedules) — P6-F5 ──────────────────────
      //
      // Same top-level shape as Customers/Vehicles/Services above: none of
      // these is a bottom-nav destination, so each lands as a full screen
      // above the shell. `EmployeeListScreen`/`EmployeeDetailScreen`/
      // `EmployeeFormScreen`/`EmployeeBulkScreen` (P6-F2),
      // `RoleListScreen`/`RoleFormScreen` (P6-F3), and
      // `ScheduleGridScreen`/`MyScheduleScreen` (P6-F4) all already expose
      // the same `onSelect*`/`onCreate*`/`onSaved` hooks
      // `ServiceListScreen` established, wired here without touching any of
      // those screens. Literal paths (`new`, `bulk`, `edit`) are registered
      // ahead of `:id` siblings, matching `services`'s convention.
      //
      // Neither `EmployeeDetailScreen.onEdit` nor `RoleListScreen
      // .onSelectRole` hands this router a full domain object to edit —
      // the former only carries an id, and a cold deep link into
      // `/employees/:id/edit` or `/roles/:id/edit` never has one either —
      // so `_EmployeeEditRoute`/`_RoleEditRoute` below fetch the record by
      // id themselves before handing it to the form screen, exactly the
      // shape `EmployeeDetailScreen`/`ServiceDetailScreen` already use for
      // their own id-only cold-start contract.
      GoRoute(
        path: AppRoutes.employees,
        builder: (context, state) => _EmployeeListRoute(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) =>
                EmployeeFormScreen(onSaved: (_) => AppNav.back()),
          ),
          GoRoute(
            path: 'bulk',
            builder: (context, state) => const EmployeeBulkScreen(),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || id.isEmpty) {
                return const _MissingEmployeeRoute();
              }
              return EmployeeDetailScreen(
                employeeId: id,
                onEdit: (employeeId) =>
                    AppNav.push('${AppRoutes.employees}/$employeeId/edit'),
              );
            },
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final id = state.pathParameters['id'];
                  if (id == null || id.isEmpty) {
                    return const _MissingEmployeeRoute();
                  }
                  return _EmployeeEditRoute(employeeId: id);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.roles,
        builder: (context, state) => _RoleListRoute(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) =>
                RoleFormScreen(onSaved: () => AppNav.back()),
          ),
          GoRoute(
            // Bare `/roles/:id` has no screen of its own — roles have no
            // standalone detail view, only the owner-only edit form — so
            // this redirects straight to `edit` rather than needing a
            // `builder` for a location nothing links to directly.
            path: ':id',
            redirect: (context, state) =>
                '${AppRoutes.roles}/${state.pathParameters['id']}/edit',
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final id = state.pathParameters['id'];
                  if (id == null || id.isEmpty) {
                    return const _MissingRoleRoute();
                  }
                  return _RoleEditRoute(roleId: id);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.schedules,
        builder: (_, _) => const ScheduleGridScreen(),
      ),
      GoRoute(
        path: AppRoutes.mySchedule,
        builder: (_, _) => const MyScheduleScreen(),
      ),

      // ── Удирдлага (Reports/Audit/Feedback) — P7-F4 ──────────────────────
      //
      // Same top-level shape as Хүмүүс above: none of these is a bottom-nav
      // destination. `ReportsScreen`/`AuditListScreen` (P7-F2/F3) need no
      // wiring beyond a bare route — both default their own repository and
      // user from `Authenticator.user` when none is injected, and
      // `ReportsScreen` already owns its `share_plus` export fallback.
      // Feedback's create/detail hooks are wired the same way
      // `_EmployeeListRoute` wires `EmployeeListScreen`'s.
      GoRoute(
        path: AppRoutes.reports,
        builder: (_, _) => const ReportsScreen(),
      ),
      GoRoute(
        path: AppRoutes.audit,
        builder: (_, _) => const AuditListScreen(),
      ),
      GoRoute(
        path: AppRoutes.feedback,
        builder: (context, state) => _FeedbackListRoute(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) =>
                FeedbackCreateScreen(onCreated: (_) => AppNav.back(true)),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = state.pathParameters['id'];
              if (id == null || id.isEmpty) {
                return const _MissingFeedbackRoute();
              }
              return FeedbackDetailScreen(feedbackId: id);
            },
          ),
        ],
      ),

      // ── Профайл (edit / password / sessions) — P8-F3 ────────────────────
      //
      // Same top-level shape as Хүмүүс/Удирдлага above: none of these is a
      // bottom-nav destination, and `ProfileScreen` itself is still pushed
      // imperatively from `AppShell`'s "More" menu (not a GoRoute). Each
      // screen already defaults its own repository/user when none is
      // injected, matching `ReportsScreen`/`AuditListScreen`'s convention.
      // `onSaved`/`onChanged` pop back to whatever pushed the route — for a
      // GoRoute push that is always `ProfileScreen`, which reloads its user
      // from `Authenticator.user` (already updated in Hive by the
      // repository call) the next time it rebuilds.
      GoRoute(
        path: AppRoutes.profileEdit,
        builder: (context, _) =>
            EditProfileScreen(onSaved: (_) => AppNav.back()),
      ),
      GoRoute(
        path: AppRoutes.profilePassword,
        builder: (context, _) =>
            ChangePasswordScreen(onChanged: () => AppNav.back()),
      ),
      GoRoute(
        path: AppRoutes.profileSessions,
        builder: (_, _) => const SessionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.profileClosure,
        builder: (_, _) => const AccountClosureScreen(),
      ),

      // Search is a global utility (top-bar action on every tab), not a
      // navigation destination, so it lives above the shell like Profile.
      GoRoute(path: AppRoutes.search, builder: (_, _) => const SearchScreen()),

      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: AppNav.tabKey(0),
            observers: [ShellDepthTracker.instance.observerFor(0)],
            routes: [
              GoRoute(
                path: AppRoutes.overview,
                // Work-first home for anyone who can see orders; the
                // general overview stays for roles without order access.
                builder: (_, _) => canSeeView(Authenticator.user, 'orders')
                    ? const TodayScreen()
                    : const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: AppNav.tabKey(1),
            observers: [ShellDepthTracker.instance.observerFor(1)],
            routes: [
              GoRoute(
                path: AppRoutes.orders,
                builder: (_, _) => const OrderListScreen(),
                routes: [
                  GoRoute(
                    path: 'in-progress',
                    builder: (_, _) => const _InProgressRoute(),
                  ),
                  GoRoute(
                    path: 'postpaid',
                    builder: (context, _) => PostpaidScreen(
                      repository: context.read<OrdersRepository>(),
                      branchController: _workingBranchController(context),
                    ),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) {
                      final id = state.pathParameters['id'];
                      if (id == null || id.isEmpty) {
                        return const _MissingOrderRoute();
                      }
                      return _orderDetail(context, id);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: AppNav.tabKey(2),
            observers: [ShellDepthTracker.instance.observerFor(2)],
            routes: [
              GoRoute(
                path: AppRoutes.appointments,
                builder: (_, _) => const AppointmentScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => AppointmentDetailRoute(
                      appointmentId: state.pathParameters['id'] ?? '',
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: AppNav.tabKey(3),
            observers: [ShellDepthTracker.instance.observerFor(3)],
            routes: [
              GoRoute(
                path: AppRoutes.more,
                builder: (_, _) => const MoreScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  AppNav.attach(router);
  AppNav.addPages(AppPages.all);
  return router;
}

/// Gives the in-progress board its own list/detail controller. The main
/// Orders destination keeps its filters and pagination independent from this
/// status-specific view.
class _InProgressRoute extends StatefulWidget {
  const _InProgressRoute();

  @override
  State<_InProgressRoute> createState() => _InProgressRouteState();
}

class _InProgressRouteState extends State<_InProgressRoute> {
  OrderController? _controller;
  WorkingBranchController? _branchController;
  String? _lastBranch;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= OrderController(repo: context.read<OrdersRepository>());
    WorkingBranchController? next;
    try {
      next = context.read<WorkingBranchController>();
    } on ProviderNotFoundException {
      next = null;
    }
    if (next == null || identical(next, _branchController)) return;
    _branchController?.removeListener(_branchChanged);
    _branchController = next;
    _lastBranch = next.selectedBranchId;
    next.addListener(_branchChanged);
  }

  void _branchChanged() {
    final branch = _branchController?.selectedBranchId;
    if (branch == _lastBranch || !mounted) return;
    _lastBranch = branch;
    // The working-branch header is owned by the repository/network layer. A
    // refresh preserves this screen's IN_PROGRESS filter without touching the
    // separate controller used by the main Orders list.
    unawaited(_controller!.refresh());
  }

  @override
  void dispose() {
    _branchController?.removeListener(_branchChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider<OrderController>.value(
        value: _controller!,
        child: const InProgressScreen(),
      );
}

/// The order detail page — `/orders/:id` inside the Orders tab, and
/// [AppPages.orderDetail] full-screen. Only the tab one has the shell's list
/// and branch controllers; the full-screen one's caller refreshes its list
/// when the page closes, and the branch cannot change while it covers the
/// shell.
Widget _orderDetail(BuildContext context, String id) => ChangeNotifierProvider(
  create: (_) => OrderDetailController(
    repo: context.read<OrdersRepository>(),
    listController: _maybeRead<OrderController>(context),
    branchController: _workingBranchController(context),
  ),
  child: OrderDetailScreen(orderId: id),
);

WorkingBranchController? _workingBranchController(BuildContext context) =>
    _maybeRead<WorkingBranchController>(context);

T? _maybeRead<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}

Future<String?> _redirect(
  BuildContext context,
  GoRouterState state,
  AuthController authController,
) async {
  final atSplash = state.matchedLocation == AppRoutes.splash;
  final atLogin = state.matchedLocation == AppRoutes.login;
  final atLocked = state.matchedLocation == AppRoutes.locked;
  final atConsent = state.matchedLocation == AppRoutes.consent;

  if (authController.authState == AuthState.finding) {
    return atSplash ? null : AppRoutes.splash;
  }

  final signedIn = authController.authState == AuthState.authorized;
  if (!signedIn) {
    if (atLogin) return null;
    final intended = state.uri.toString();
    if (intended == AppRoutes.splash) return AppRoutes.login;
    return Uri(
      path: AppRoutes.login,
      queryParameters: {'from': intended},
    ).toString();
  }

  // The terms come first — before any page and the subscription lock —
  // right after a successful login, and for an existing session that has
  // not accepted the current version. The intended page rides along.
  final userId = Authenticator.user?.id;
  if (userId != null && !LegalConsentStore.instance.hasAccepted(userId)) {
    if (atConsent) return null;
    final from = atLogin || atSplash
        ? state.uri.queryParameters['from']
        : state.uri.toString();
    return Uri(
      path: AppRoutes.consent,
      queryParameters: {
        if (from != null &&
            from.isNotEmpty &&
            from != AppRoutes.login &&
            from != AppRoutes.splash)
          'from': from,
      },
    ).toString();
  }

  if (atLogin || atSplash || atConsent) {
    final from = state.uri.queryParameters['from'];
    if (from != null && from.isNotEmpty && from != AppRoutes.login) return from;
    return AppRoutes.overview;
  }

  if (!atLocked) {
    final status = await SubscriptionService.instance.getStatus();
    if (status?.locked == true) return AppRoutes.locked;
  } else {
    final status = await SubscriptionService.instance.getStatus();
    if (status?.locked != true) return AppRoutes.overview;
  }
  return null;
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _MissingOrderRoute extends StatelessWidget {
  const _MissingOrderRoute();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Засварын хуудасны дугаар буруу байна')));
}

/// `/customers` — wraps the existing `CustomerSearchTab` (P3-F2) in its own
/// Scaffold/AppBar so it is reachable as a standalone deep-linkable route,
/// not only as a tab of `SearchScreen`. `CustomerSearchTab` itself still
/// pushes `CustomerDetailScreen` imperatively for its in-tab navigation —
/// left untouched, since that file is owned by a concurrent slice — this
/// route only gives the tab's content a real URL from the outside.
class _CustomerListRoute extends StatelessWidget {
  const _CustomerListRoute();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Үйлчлүүлэгчид')),
    body: const CustomerSearchTab(),
  );
}

class _MissingCustomerRoute extends StatelessWidget {
  const _MissingCustomerRoute();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Text('Үйлчлүүлэгчийн дугаар буруу байна')),
  );
}

/// `/vehicles` — the standalone `VehicleListScreen` (P3-F3), which already
/// owns its own Scaffold/AppBar and was left with only an `onSelectVehicle`
/// hook plus an explicit note that no route existed yet for the vehicle
/// detail screen. This wires that hook to the new `/vehicles/:id` route via
/// `context.push`, so the back stack keeps the list underneath rather than
/// replacing it.
class _VehicleListRoute extends StatelessWidget {
  const _VehicleListRoute();

  @override
  Widget build(BuildContext context) => VehicleListScreen(
    onSelectVehicle: (Vehicle vehicle) =>
        AppNav.push('${AppRoutes.vehicles}/${vehicle.id}'),
    onCreateVehicle: () async =>
        await AppNav.push<NewVehicleResult>('${AppRoutes.vehicles}/new') !=
        null,
  );
}

class _MissingVehicleRoute extends StatelessWidget {
  const _MissingVehicleRoute();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Машины дугаар буруу байна')));
}

/// `/services` — the standalone `ServiceListScreen` (P4-F2). Wires
/// `onSelectService` to push `/services/:id` (list stays underneath on the
/// back stack, same as `_VehicleListRoute`) and `onCreateService` to push
/// `/services/new` carrying the tapped kind tab as a `?type=` query param, so
/// a cold deep link into the create screen still lands on the right kind.
///
/// [initialType] seeds which kind-filter tab `ServiceListScreen` opens on —
/// the "Каталог" drawer's Хөдөлмөр/Бараа entries (`app_shell.dart`) link
/// here with an explicit `?type=`, closing the gap the Phase 4 entry state
/// flagged: those two rows previously had no destination and no way to tell
/// the list which kind to preselect.
class _ServiceListRoute extends StatelessWidget {
  const _ServiceListRoute({this.initialType});

  final ServiceKind? initialType;

  @override
  Widget build(BuildContext context) => ServiceListScreen(
    initialType: initialType,
    onSelectService: (Service service) =>
        AppNav.push('${AppRoutes.services}/${service.id}'),
    onCreateService: (ServiceKind kind) => AppNav.push(
      Uri(
        path: '${AppRoutes.services}/new',
        queryParameters: {'type': _serviceKindParam(kind)},
      ).toString(),
    ),
  );
}

class _MissingServiceRoute extends StatelessWidget {
  const _MissingServiceRoute();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Text('Үйлчилгээний дугаар буруу байна')),
  );
}

class _MissingDiagnosticRoute extends StatelessWidget {
  const _MissingDiagnosticRoute();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Text('Оношилгооны дугаар буруу байна')),
  );
}

/// Route-local `?type=` encoding for [ServiceKind] — deliberately not
/// `ServiceKind.wire`/`fromWire` (`LABOR`/`GOODS`/`DIAGNOSTIC`), which is the
/// API's own contract, not a URL query convention. Unknown/missing values
/// return `null` rather than guessing, so a garbled deep link falls back to
/// `ServiceListScreen`'s own default (the labor tab) instead of silently
/// picking a kind nobody asked for.
String _serviceKindParam(ServiceKind kind) => switch (kind) {
  ServiceKind.labor => 'labor',
  ServiceKind.goods => 'goods',
  ServiceKind.diagnostic => 'diagnostic',
  ServiceKind.unknown => 'labor',
};

ServiceKind? _parseServiceKindParam(String? value) => switch (value) {
  'labor' => ServiceKind.labor,
  'goods' => ServiceKind.goods,
  'diagnostic' => ServiceKind.diagnostic,
  _ => null,
};

// ── Хүмүүс route wrappers — P6-F5 ──────────────────────────────────────

/// `/employees` — wires [EmployeeListScreen]'s hooks the same way
/// `_ServiceListRoute` wires `ServiceListScreen`'s.
class _EmployeeListRoute extends StatelessWidget {
  const _EmployeeListRoute();

  @override
  Widget build(BuildContext context) => EmployeeListScreen(
    onTapRow: (employee) =>
        AppNav.push('${AppRoutes.employees}/${employee.id}'),
    onCreate: () => AppNav.push('${AppRoutes.employees}/new'),
    onBulkEdit: () => AppNav.push('${AppRoutes.employees}/bulk'),
  );
}

class _MissingEmployeeRoute extends StatelessWidget {
  const _MissingEmployeeRoute();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Ажилтны дугаар буруу байна')));
}

/// `/employees/:id/edit` — `EmployeeDetailScreen.onEdit` only carries an id
/// (see this section's doc comment above), so this fetches the [Employee]
/// itself before handing it to [EmployeeFormScreen], the same one-time fetch
/// shape a cold deep link into this path would need anyway.
class _EmployeeEditRoute extends StatefulWidget {
  const _EmployeeEditRoute({required this.employeeId});

  final String employeeId;

  @override
  State<_EmployeeEditRoute> createState() => _EmployeeEditRouteState();
}

class _EmployeeEditRouteState extends State<_EmployeeEditRoute> {
  final EmployeesRepository _repo = RemoteEmployeesRepository();
  late final Future<Result<Employee>> _future = _repo.getEmployee(
    widget.employeeId,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Result<Employee>>(
    future: _future,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final result = snapshot.data!;
      if (result is! Ok<Employee>) {
        return const _MissingEmployeeRoute();
      }
      return EmployeeFormScreen(
        employee: result.value,
        repo: _repo,
        onSaved: (_) => AppNav.back(),
      );
    },
  );
}

/// `/roles` — wires [RoleListScreen]'s hooks straight to the edit route:
/// there is no standalone role detail screen (see the `:id` `GoRoute`'s doc
/// comment above).
class _RoleListRoute extends StatelessWidget {
  const _RoleListRoute();

  @override
  Widget build(BuildContext context) => RoleListScreen(
    onSelectRole: (role) => AppNav.push('${AppRoutes.roles}/${role.id}/edit'),
    onCreateRole: () => AppNav.push('${AppRoutes.roles}/new'),
  );
}

class _MissingRoleRoute extends StatelessWidget {
  const _MissingRoleRoute();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Үүргийн дугаар буруу байна')));
}

// ── Удирдлага route wrappers — P7-F4 ────────────────────────────────────

/// `/feedback` — wires [FeedbackListScreen]'s hooks: tapping a ticket pushes
/// its detail (list stays underneath on the back stack, same as
/// `_VehicleListRoute`), and creating pushes `/feedback/new`. A truthy pop
/// from the create screen (see `onCreated` above) means a ticket was
/// submitted, so the list refreshes instead of showing stale data.
class _FeedbackListRoute extends StatefulWidget {
  @override
  State<_FeedbackListRoute> createState() => _FeedbackListRouteState();
}

class _FeedbackListRouteState extends State<_FeedbackListRoute> {
  Key _key = UniqueKey();

  @override
  Widget build(BuildContext context) => FeedbackListScreen(
    key: _key,
    onTapTicket: (feedback_domain.Feedback ticket) =>
        AppNav.push('${AppRoutes.feedback}/${ticket.id}'),
    onCreate: () async {
      final created = await AppNav.push<bool>('${AppRoutes.feedback}/new');
      if (created == true && mounted) setState(() => _key = UniqueKey());
    },
  );
}

class _MissingFeedbackRoute extends StatelessWidget {
  const _MissingFeedbackRoute();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Text('Санал хүсэлтийн дугаар буруу байна')),
  );
}

/// `/roles/:id/edit` — fetches the [Role] by id before handing it to
/// [RoleFormScreen], matching `_EmployeeEditRoute`'s shape: neither a cold
/// deep link nor the `:id` redirect above carries a full [Role] object.
class _RoleEditRoute extends StatefulWidget {
  const _RoleEditRoute({required this.roleId});

  final String roleId;

  @override
  State<_RoleEditRoute> createState() => _RoleEditRouteState();
}

class _RoleEditRouteState extends State<_RoleEditRoute> {
  final RolesRepository _repo = RemoteRolesRepository();
  late final Future<Result<Role>> _future = _repo.getRole(widget.roleId);

  @override
  Widget build(BuildContext context) => FutureBuilder<Result<Role>>(
    future: _future,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final result = snapshot.data!;
      if (result is! Ok<Role>) {
        return const _MissingRoleRoute();
      }
      return RoleFormScreen(
        existing: result.value,
        rolesRepository: _repo,
        onSaved: () => AppNav.back(),
      );
    },
  );
}
