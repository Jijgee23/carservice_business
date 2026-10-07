import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:carservice_business/features/customers/presentation/controllers/customer_org_form_controller.dart';

/// "Байгууллага" switch + the three org fields it reveals (Phase 4). Shared
/// by the new-customer and edit sheets; state lives in
/// [CustomerOrgFormController]. Field errors from the server are passed in
/// by key (`orgRegnum`, `orgName`, `orgEmail`).
class CustomerOrgSection extends StatelessWidget {
  const CustomerOrgSection({
    super.key,
    required this.controller,
    this.fieldErrors = const {},
  });

  final CustomerOrgFormController controller;
  final Map<String, String> fieldErrors;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final isOrg = controller.isOrganization;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Байгууллага')),
                Switch(
                  key: const Key('customer-org-switch'),
                  value: isOrg,
                  onChanged: controller.setOrganization,
                ),
              ],
            ),
            if (isOrg) ...[
              TextFormField(
                key: const Key('customer-org-regnum'),
                controller: controller.regnumCtrl,
                keyboardType: TextInputType.number,
                maxLength: 7,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: controller.validateRegnum,
                decoration: InputDecoration(
                  labelText: 'Регистрийн дугаар',
                  counterText: '',
                  errorText: fieldErrors['orgRegnum'],
                  suffixIcon: controller.lookingUp
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  helperText: controller.lookupError,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('customer-org-name'),
                controller: controller.nameCtrl,
                textCapitalization: TextCapitalization.words,
                validator: controller.validateName,
                decoration: InputDecoration(
                  labelText: 'Байгууллагын нэр *',
                  errorText: fieldErrors['orgName'],
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('customer-org-email'),
                controller: controller.emailCtrl,
                keyboardType: TextInputType.emailAddress,
                validator: controller.validateEmail,
                decoration: InputDecoration(
                  labelText: 'Байгууллагын имэйл',
                  errorText: fieldErrors['orgEmail'],
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Доорх нэр, утас нь холбогдох хүний мэдээлэл.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ],
        );
      },
    );
  }
}
