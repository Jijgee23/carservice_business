import 'package:carservice_business/core/domain/user.dart';

/// Permission that closes a postpaid order unpaid and, once it is COMPLETED,
/// lets the holder record/reverse its payments (accountant). Owner implicit.
const closeUnpaidPostpaidPermission = 'orders.closeUnpaidPostpaid';

/// Shown instead of the payment actions when settlement is not allowed.
const postpaidSettlementNote =
    'Дууссан дараа тооцоот захиалгын төлбөрийг нягтлан бүртгэнэ.';

bool userCanSettlePostpaid(User? user) =>
    user?.isOwner == true ||
    (user?.role?.permissions.contains(closeUnpaidPostpaidPermission) ?? false);

/// Shown instead of the payment section for an internal repair.
const internalOrderPaymentNote =
    'Дотоод засвар — төлбөргүй, дотоод зардалд бүртгэгдэнэ.';
