import 'package:flutter/material.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/errors/app_error.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/customers/domain/customer.dart';
import 'package:carservice_business/features/customers/presentation/controllers/customer_detail_controller.dart';
import 'package:carservice_business/features/customers/presentation/controllers/customer_org_form_controller.dart';
import 'package:carservice_business/features/customers/presentation/widgets/customer_org_section.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';

/// Edit form for a [Customer] — P3-F4.
///
/// `PATCH /customers/[id]` is a whole-record replace: an omitted field
/// clears the column server-side. This form therefore always sends all four
/// of fullName/phone/email/note explicitly (empty string where the field is
/// blank), never a subset — there is no "only changed fields" diff logic to
/// accidentally reintroduce the omission hazard the contract warns about.
class CustomerEditSheet extends StatefulWidget {
  const CustomerEditSheet({
    super.key,
    required this.customer,
    required this.controller,
  });

  final Customer customer;
  final CustomerDetailController controller;

  static Future<bool> show(
    BuildContext context, {
    required Customer customer,
    required CustomerDetailController controller,
  }) async {
    final result = await AppNav.sheet<bool>(
      CustomerEditSheet(customer: customer, controller: controller),
      backgroundColor: Colors.transparent,
    );
    return result ?? false;
  }

  @override
  State<CustomerEditSheet> createState() => _CustomerEditSheetState();
}

class _CustomerEditSheetState extends State<CustomerEditSheet> {
  late final _nameCtrl = TextEditingController(
    text: widget.customer.fullName ?? '',
  );
  late final _phoneCtrl = TextEditingController(
    text: widget.customer.phone ?? '',
  );
  late final _emailCtrl = TextEditingController(
    text: widget.customer.email ?? '',
  );
  late final _noteCtrl = TextEditingController(
    text: widget.customer.note ?? '',
  );

  /// Name is capped at 100 only when the stored value already fits.
  late final bool _nameCapped = (widget.customer.fullName ?? '').length <= 100;

  late final CustomerOrgFormController _org = CustomerOrgFormController(
    repository: widget.controller.repository,
    initial: widget.customer,
  );
  final _formKey = GlobalKey<FormState>();

  bool _saving = false;
  String? _generalError;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _noteCtrl.dispose();
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
    // All four fields explicitly, always — see the class doc comment.
    final result = await widget.controller.update(
      fullName: _nameCtrl.text,
      phone: _phoneCtrl.text,
      email: _emailCtrl.text,
      note: _noteCtrl.text,
      isOrganization: _org.isOrganization,
      orgRegnum: _org.orgRegnum,
      orgName: _org.orgName,
      orgEmail: _org.orgEmail,
    );
    if (!mounted) return;
    switch (result) {
      case Ok():
        AppNav.back(true);
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Үйлчлүүлэгч засах', style: context.textStyles.h3),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_generalError != null) ...[
                        Text(
                          _generalError!,
                          style: context.textStyles.body.copyWith(
                            color: context.colors.danger,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      CustomerOrgSection(
                        controller: _org,
                        fieldErrors: _fieldErrors,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameCtrl,
                        // Server max is 100. An already-longer stored name must
                        // not be truncated, so only cap when it fits.
                        maxLength: _nameCapped ? 100 : null,
                        decoration: InputDecoration(
                          counterText: _nameCapped ? '' : null,
                          labelText: 'Нэр',
                          errorText: _fieldErrors['fullName'],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Утас',
                          errorText: _fieldErrors['phone'],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Имэйл',
                          errorText: _fieldErrors['email'],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _noteCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Тэмдэглэл',
                          errorText: _fieldErrors['note'],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => AppNav.back(false),
                    child: const Text('Болих'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const AppLoading(size: 18)
                        : const Text('Хадгалах'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
