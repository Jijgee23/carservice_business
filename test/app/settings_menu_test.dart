import 'package:carservice_business/app/router.dart';
import 'package:carservice_business/app/shell/app_shell.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:flutter_test/flutter_test.dart';

User _user({bool isOwner = false, List<String> permissions = const []}) => User(
  accessToken: 'a',
  refreshToken: 'r',
  id: 'u1',
  email: 'u@x.mn',
  firstName: 'Бат',
  lastName: 'Болд',
  phone: '99112233',
  isOwner: isOwner,
  role: UserRole('r1', 'Ажилтан', permissions),
  tenant: UserTenant('t1', 'Авто'),
);

void main() {
  dynamic group() => MoreScreen.groups.firstWhere((g) => g.label == 'Тохиргоо');

  List<String> visible(User user) => [
    for (final e in group().entries)
      if (canSeeView(user, e.permission as String?)) e.label as String,
  ];

  test('Тохиргоо rows carry real routes', () {
    expect(
      [for (final e in group().entries) e.route],
      [AppRoutes.organizationSettings, AppRoutes.branches],
    );
  });

  test('owner sees both rows', () {
    expect(visible(_user(isOwner: true)), ['Байгууллага', 'Салбарууд']);
  });

  test('staff with branches.view sees only Салбарууд', () {
    expect(visible(_user(permissions: const ['branches.view'])), ['Салбарууд']);
  });

  test('staff without branch permissions sees neither', () {
    expect(visible(_user(permissions: const ['orders.view'])), isEmpty);
  });
}
