import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/utils/validators.dart';
import 'package:carservice_business/core/domain/diagnostic.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/customers/data/customer_repository.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';
import 'package:carservice_business/features/customers/domain/customers_repository.dart';
import 'package:carservice_business/features/customers/presentation/controllers/customer_org_form_controller.dart';
import 'package:carservice_business/features/customers/presentation/widgets/customer_org_section.dart';
import 'package:flutter/material.dart';
import 'package:carservice_business/features/orders/presentation/feature_theme.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// Quick-create customer sheet — promoted onto [CustomersRepository]
/// (`P3-F1`) for `P3-F6`.
///
/// The Orders create flow (`create_order_screen.dart`) depends on this sheet
/// for its inline "create a customer without leaving the order" fast path —
/// see `AppointmentsRepository`'s sibling precedent — so the shape stays a
/// modal bottom sheet returning a [CustomerSummary] the caller can use
/// immediately, never a full-screen form or a round trip through a detail
/// screen. Only the data source moved off `DiagnosticService`.
///
/// `POST /customers` returns 201 for a genuine create and 200 for an
/// account-claim/reuse — both are [Ok] here, exactly per the frozen
/// contract; this sheet does not care which happened; see
/// `CustomerCreateResult.created`. A 422 is classified by the repository's
/// typed [Result] — [AppError.fieldErrors] present means validation
/// (bind to the field), absent means a plan-limit message to show verbatim.
Future<CustomerSummary?> showNewCustomerSheet(
  BuildContext context, {
  CustomersRepository? repository,
}) {
  return AppNav.sheet<CustomerSummary>(
    _NewCustomerSheet(repository: repository),
    backgroundColor: Colors.transparent,
  );
}

class _NewCustomerSheet extends StatefulWidget {
  const _NewCustomerSheet({this.repository});

  final CustomersRepository? repository;

  @override
  State<_NewCustomerSheet> createState() => _NewCustomerSheetState();
}

class _NewCustomerSheetState extends State<_NewCustomerSheet>
    with ValidatorMixin {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  late final CustomersRepository _repo =
      widget.repository ?? RemoteCustomersRepository();
  late final CustomerOrgFormController _org = CustomerOrgFormController(
    repository: _repo,
  );
  bool _saving = false;
  String? _generalError;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _org.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _generalError = null;
      _fieldErrors = const {};
    });
    final phone = _phoneCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final result = await _repo.createCustomer(
      fullName: name.isEmpty ? null : name,
      phone: phone,
      email: email.isEmpty ? null : email,
      isOrganization: _org.isOrganization,
      orgRegnum: _org.orgRegnum,
      orgName: _org.orgName,
      orgEmail: _org.orgEmail,
    );
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        setState(() => _saving = false);
        final customer = value.customer;
        AppNav.back(
          CustomerSummary(
            id: customer.id,
            fullName: customer.fullName,
            // `phone` is mandatory on the frozen contract but is modelled
            // nullable on `Customer`; fall back to what was sent rather than
            // an empty string, matching the fast-path type's requirement.
            phone: customer.phone ?? phone,
            email: customer.email,
            isOrganization: customer.isOrganization,
            orgName: customer.orgName,
          ),
        );
      case Err(:final error):
        setState(() {
          _saving = false;
          _fieldErrors = error.fieldErrors ?? const {};
          _generalError =
              (error.fieldErrors == null || error.fieldErrors!.isEmpty)
              ? error.display
              : null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Full-height sheet: the submit button sits at the very bottom, so clear
    // the keyboard when it is open, otherwise the home indicator.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final systemBottom = MediaQuery.paddingOf(context).bottom;
    final bottom = keyboard > systemBottom ? keyboard : systemBottom;

    return Container(
      decoration: BoxDecoration(
        color: context.opsSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.opsDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: context.opsAccent.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_add_outlined,
                    size: 18,
                    color: context.opsAccent,
                  ),
                ),
                const SizedBox(width: 10),
                Text('Шинэ үйлчлүүлэгч', style: context.textStyles.h3),
              ],
            ),
            const SizedBox(height: 20),

            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_generalError != null) ...[
                      Text(
                        _generalError!,
                        style: TextStyle(color: context.opsDanger),
                      ),
                      const SizedBox(height: 12),
                    ],

                    CustomerOrgSection(
                      controller: _org,
                      fieldErrors: _fieldErrors,
                    ),
                    const SizedBox(height: 4),
                    _Field(
                      label: 'Овог нэр',
                      ctrl: _nameCtrl,
                      hint: 'Дорж Батбаяр (заавал биш)',
                      textCapitalization: TextCapitalization.words,
                      errorText: _fieldErrors['fullName'],
                      maxLength: 100,
                    ),
                    const SizedBox(height: 12),

                    _Field(
                      label: 'Утасны дугаар *',
                      ctrl: _phoneCtrl,
                      hint: '99112233',
                      keyboardType: TextInputType.phone,
                      validator: phoneValidator,
                      errorText: _fieldErrors['phone'],
                    ),
                    const SizedBox(height: 12),

                    _Field(
                      label: 'И-мэйл',
                      ctrl: _emailCtrl,
                      hint: 'name@example.mn',
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? null
                          : AppValidators.email(v),
                      errorText: _fieldErrors['email'],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.opsTextOnDark,
                        ),
                      )
                    : Text(
                        'Бүртгэх',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: context.opsTextOnDark,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String hint;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final TextCapitalization textCapitalization;
  final String? errorText;
  final int? maxLength;

  const _Field({
    required this.label,
    required this.ctrl,
    required this.hint,
    this.keyboardType,
    this.validator,
    this.textCapitalization = TextCapitalization.none,
    this.errorText,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.opsTextPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          validator: validator,
          style: context.textStyles.body,
          maxLength: maxLength,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            counterText: maxLength == null ? null : '',
          ),
        ),
      ],
    );
  }
}
