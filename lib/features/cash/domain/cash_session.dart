import 'package:carservice_business/core/errors/app_error.dart';

/// Reason shown next to a disabled money action while the branch has no open
/// register session (same text as the server's CASH_SESSION_CLOSED 409).
const kNoCashSessionWarning = CashSessionClosedError.message;

/// Money writes of ANY payment method are blocked while the branch is known
/// to have no open session; an unknown flag (not loaded / failed) never
/// blocks locally, the server stays authoritative.
bool cashSessionBlocked(bool? sessionOpen) => sessionOpen == false;
