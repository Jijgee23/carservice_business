import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/branches/domain/branch.dart';

/// Branch management — `app/api/v1/branches/**` (permissions
/// `branches.view/create/edit/delete`, enforced server-side).
abstract interface class BranchesRepository {
  /// Every branch `GET /branches` returns (all pages), primary first.
  Future<Result<List<BranchSummary>>> listBranches();

  Future<Result<BranchDetail>> getBranch(String id);

  Future<Result<BranchDetail>> createBranch(BranchDraft draft);

  /// A `409 SCHEDULE_IMPACT` comes back as a [BranchScheduleImpactError].
  Future<Result<BranchDetail>> updateBranch(String id, BranchDraft draft, {bool confirm = false});

  /// Answers the new `isActive`.
  Future<Result<bool>> toggleActive(String id);

  Future<Result<bool>> deleteBranch(String id);

  /// Selectable business-type tags.
  Future<Result<List<BranchTag>>> listTags();

  Future<Result<BranchPinAddress>> addressAt(double lat, double lng);
}
