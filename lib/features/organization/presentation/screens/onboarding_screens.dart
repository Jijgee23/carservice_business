import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/widgets/adaptive/async_state_view.dart';
import 'package:carservice_business/core/widgets/common/ops_kit.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/features/organization/domain/organization.dart';
import 'package:carservice_business/features/organization/domain/organization_repository.dart';
import 'package:carservice_business/features/organization/domain/service_keys.dart';
import 'package:carservice_business/features/organization/presentation/controllers/service_keys_controller.dart';
import 'package:carservice_business/features/organization/presentation/controllers/tenant_onboarding_controller.dart';

/// Shared frame of the owner's blocking onboarding steps — the same centred,
/// max-520 layout as `ChooseBranchScreen`. Back cannot dismiss it.
class _GateFrame extends StatelessWidget {
  const _GateFrame({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.footer,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final t = CarserviceTheme.of(context);
    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: t.shellBackground,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = math.max(24.0, (constraints.maxWidth - 520) / 2);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(side, 24, side, 16),
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                              height: 1.2,
                              color: t.ink,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 15,
                              height: 22 / 15,
                              color: t.mutedText,
                            ),
                          ),
                          const SizedBox(height: 22),
                          child,
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(side, 8, side, 16),
                      child: footer,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// «Засварын газрынхаа нэрийг оруулна уу» — хувь хүний регистрээр
/// бүртгүүлсэн эзэнд (нэр = эзний овог нэр). Web: `shop-name-gate.tsx`.
class ShopNameGateScreen extends StatefulWidget {
  const ShopNameGateScreen({super.key, required this.controller});

  final TenantOnboardingController controller;

  @override
  State<ShopNameGateScreen> createState() => _ShopNameGateScreenState();
}

class _ShopNameGateScreenState extends State<ShopNameGateScreen> {
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final error = await widget.controller.saveShopName(_name.text);
    if (!mounted) return;
    setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final current = c.currentName.trim();
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => _GateFrame(
        title: 'Засварын газрынхаа нэрийг оруулна уу',
        subtitle:
            'Жолооч нар газрын зураг, цаг захиалга дээр танай засварыг энэ '
            'нэрээр харна.'
            '${current.isEmpty ? '' : ' Одоогоор таны овог нэр ($current) харагдаж байна.'}',
        footer: OpsPrimaryButton(
          key: const ValueKey('shop_name_save'),
          label: 'Хадгалах',
          loading: c.savingName,
          onPressed: _save,
        ),
        child: TextField(
          key: const ValueKey('shop_name_field'),
          controller: _name,
          autofocus: true,
          maxLength: ShopName.maxLength,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(
            labelText: 'Засварын нэр',
            hintText: 'Жишээ: Бат Авто Засвар',
            errorText: _error,
            errorMaxLines: 3,
          ),
        ),
      ),
    );
  }
}

/// «Танайх ямар үйлчилгээ үзүүлдэг вэ?» — эзэн үзүүлдэг үйлчилгээгээ
/// баталгаажуулаагүй үед (нэрийн алхмын дараа). Web: `service-keys-gate.tsx`.
class ServiceKeysGateScreen extends StatelessWidget {
  const ServiceKeysGateScreen({
    super.key,
    required this.onboarding,
    this.repository,
  });

  final TenantOnboardingController onboarding;
  final OrganizationRepository? repository;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => ServiceKeysController(repo: repository)..load(),
    child: Builder(
      builder: (context) {
        final c = context.watch<ServiceKeysController>();
        return _GateFrame(
          title: 'Танайх ямар үйлчилгээ үзүүлдэг вэ?',
          subtitle:
              'Жолооч нар carservice.mn дээр хийлгэх ажлаараа хайхад таны '
              'байгууллага гарч ирнэ, онлайн цаг захиалгад ашиглагдана. Үзүүлдэг '
              'бүх үйлчилгээгээ сонгоно уу — дараа нь Тохиргооноос өөрчилж болно.',
          footer: _SaveRow(
            controller: c,
            label: 'Хадгалаад үргэлжлүүлэх',
            onSaved: onboarding.serviceKeysSaved,
          ),
          child: ServiceKeysPicker(controller: c),
        );
      },
    ),
  );
}

/// Тохиргоо → «Үзүүлдэг үйлчилгээ». Бүх ажилтан харна, эзэн л засна.
class ServiceKeysScreen extends StatelessWidget {
  const ServiceKeysScreen({super.key, this.repository});

  final OrganizationRepository? repository;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => ServiceKeysController(repo: repository)..load(),
    child: Builder(
      builder: (context) {
        final c = context.watch<ServiceKeysController>();
        return Scaffold(
          backgroundColor: context.colors.background,
          appBar: AppBar(title: const Text('Үзүүлдэг үйлчилгээ')),
          bottomNavigationBar: c.canEdit
              ? OpsBottomActionBar(
                  children: [
                    Expanded(
                      child: _SaveRow(
                        controller: c,
                        label: 'Хадгалах',
                        onSaved: () => messageComplete('Хадгалагдлаа'),
                      ),
                    ),
                  ],
                )
              : null,
          body: AsyncStateView<TenantServiceKeys>(
            state: c.state,
            onRetry: c.load,
            builder: (context, data) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  'Жолооч нар /book болон газрын зураг дээр ажлаараа хайхад '
                  'танай байгууллага эдгээр үйлчилгээгээр гарна.',
                  style: context.textStyles.caption,
                ),
                if (!data.canEdit) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Зөвхөн байгууллагын эзэмшигч өөрчилнө.',
                    style: context.textStyles.caption,
                  ),
                ],
                const SizedBox(height: 12),
                ServiceKeysPicker(controller: c),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Multi-select list of the system service types (web
/// `service-keys-picker.tsx`): a search box once there are more than 8,
/// checkbox rows with the description underneath.
class ServiceKeysPicker extends StatelessWidget {
  const ServiceKeysPicker({super.key, required this.controller});

  final ServiceKeysController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final state = c.state;
    if (c.data == null) {
      return AsyncStateView<TenantServiceKeys>(
        state: state,
        onRetry: c.load,
        builder: (_, _) => const SizedBox.shrink(),
      );
    }
    final t = CarserviceTheme.of(context);
    final keys = c.data!.keys;
    final enabled = c.canEdit && !c.saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (keys.length > 8) ...[
          TextField(
            key: const ValueKey('service_keys_search'),
            onChanged: c.setQuery,
            decoration: const InputDecoration(
              hintText: 'Үйлчилгээ хайх…',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final k in c.visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: c.selected.contains(k.id)
                  ? t.accent.withValues(alpha: 0.10)
                  : t.panel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: c.selected.contains(k.id) ? t.accent : t.border,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: CheckboxListTile(
                key: ValueKey('service_key_${k.id}'),
                value: c.selected.contains(k.id),
                onChanged: enabled ? (_) => c.toggle(k.id) : null,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: t.accent,
                dense: true,
                title: Text(
                  k.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                subtitle: k.description == null
                    ? null
                    : Text(
                        k.description!,
                        style: TextStyle(fontSize: 12, color: t.mutedText),
                      ),
              ),
            ),
          ),
        if (keys.isEmpty)
          Text(
            'Үйлчилгээний төрөл олдсонгүй.',
            style: context.textStyles.caption,
          ),
      ],
    );
  }
}

class _SaveRow extends StatelessWidget {
  const _SaveRow({
    required this.controller,
    required this.label,
    required this.onSaved,
  });

  final ServiceKeysController controller;
  final String label;
  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = CarserviceTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.error != null) ...[
          Text(
            c.error!,
            key: const ValueKey('service_keys_error'),
            style: TextStyle(fontSize: 13, color: t.danger),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Text(
              '${c.selected.length} сонгосон',
              style: TextStyle(fontSize: 12, color: t.mutedText),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OpsPrimaryButton(
                key: const ValueKey('service_keys_save'),
                label: label,
                loading: c.saving,
                onPressed: c.data == null || c.selected.isEmpty || !c.canEdit
                    ? null
                    : () async {
                        if (await c.save()) onSaved();
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
