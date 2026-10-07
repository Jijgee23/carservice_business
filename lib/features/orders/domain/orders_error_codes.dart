import 'package:carservice_business/core/errors/app_error.dart';

abstract final class OrdersErrorCodes {
  static const confirmationRequired = 'CONFIRMATION_REQUIRED';
  static const paidPaymentLocked = 'PAID_PAYMENT_LOCKED';
  static const paidPaymentLockedCancelMessage =
      'Төлбөр нь хаагдсан ээлжид бүртгэгдсэн тул захиалгыг цуцлах боломжгүй.';
  static const paidPaymentLockedItemMessage =
      'Төлбөр нь хаагдсан ээлжид бүртгэгдсэн тул мөрийг засах, цуцлах боломжгүй.';
  static const paidPaymentExists = 'PAID_PAYMENT_EXISTS';
  static const assigneeRequired = 'ASSIGNEE_REQUIRED';
  static const itemsNotCompleted = 'ITEMS_NOT_COMPLETED';
  static const paymentIncomplete = 'PAYMENT_INCOMPLETE';
  static const postpaidCloseForbidden = 'POSTPAID_CLOSE_FORBIDDEN';
  static const postpaidSettlementForbidden = 'POSTPAID_SETTLEMENT_FORBIDDEN';
  static const postpaidSettlementForbiddenMessage =
      'Дууссан дараа тооцоот захиалгын төлбөрийг зөвхөн эрхтэй хэрэглэгч (нягтлан) бүртгэнэ.';
  static const internalPostpaidConflict = 'ORDER_INTERNAL_POSTPAID_CONFLICT';
  static const internalPostpaidConflictMessage =
      'Дотоод засвар болон дараа тооцоо зэрэг байж болохгүй.';
  static const paymentBankRequired = 'PAYMENT_BANK_REQUIRED';
  static const paymentBankRequiredMessage = 'Банкаа сонгоно уу.';
  static const cashSessionEntryLocked = CashSessionEntryLockedError.code;
  static const cashSessionEntryLockedMessage =
      CashSessionEntryLockedError.message;
  static const settlementPaymentLocked = 'SETTLEMENT_PAYMENT_LOCKED';
  static const settlementPaymentLockedMessage =
      'Нэгдсэн тооцооны төлбөрийг тооцоогоор нь цуцална уу.';
  static const internalNoPayment = 'ORDER_INTERNAL_NO_PAYMENT';
  static const internalNoPaymentMessage = 'Дотоод засварт төлбөр бүртгэхгүй.';
  static const internalHasPayments = 'ORDER_INTERNAL_HAS_PAYMENTS';
  static const internalHasPaymentsMessage =
      'Төлбөр бүртгэгдсэн захиалгыг дотоод засвар болгох боломжгүй.';
}
