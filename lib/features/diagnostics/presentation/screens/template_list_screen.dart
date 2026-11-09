import 'package:carservice_business/app/router.dart';
import 'package:carservice_business/app/theme/app_theme.dart';
import 'package:carservice_business/core/domain/user.dart';
import 'package:carservice_business/core/services/auth_storage.dart';
import 'package:carservice_business/core/utils/money_format.dart';
import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/core/widgets/adaptive/permission_gate.dart';
import 'package:carservice_business/core/widgets/common/common_widgets.dart';
import 'package:carservice_business/core/widgets/dialogs/confirm_sheet.dart';
import 'package:carservice_business/core/widgets/dialogs/message.dart';
import 'package:carservice_business/core/widgets/list_search_bar.dart';
import 'package:carservice_business/features/diagnostics/data/diagnostics_data_source.dart';
import 'package:carservice_business/features/diagnostics/data/diagnostics_repository.dart';
import 'package:carservice_business/features/diagnostics/domain/diagnostic.dart';
import 'package:carservice_business/features/diagnostics/domain/diagnostics_repository.dart';
import 'package:carservice_business/features/diagnostics/presentation/widgets/template_widgets.dart';
import 'package:carservice_business/core/navigation/app_nav.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The diagnostic services — the web's Үйлчилгээ → Оношилгоо tab
/// (`carservice.mn/app/dashboard/services/diagnostics/page.tsx`): every
/// template, inactive ones included, with its type, price, duration and
/// version; open one to edit (or view, for system templates), duplicate or
/// delete it — one with filled reports is archived instead.
class TemplateListScreen extends StatefulWidget {
  const TemplateListScreen({super.key, this.repo, this.user});
  final DiagnosticTemplateRepository? repo;
  final User? user;

  @override
  State<TemplateListScreen> createState() => _TemplateListScreenState();
}

class _TemplateListScreenState extends State<TemplateListScreen> {
  late final DiagnosticTemplateRepository _repo =
      widget.repo ?? DiagnosticsRepositoryImpl(RemoteDiagnosticsDataSource());
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<DiagnosticTemplateSummary> _templates = const [];

  /// Null shows every type.
  DiagnosticType? _type;

  User? get _user => widget.user ?? Authenticator.user;

  @override
  void initState() {
    super.initState();
    if (canSeeView(_user, 'diagnostics.view')) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _templates.isEmpty;
      _error = null;
    });
    final result = await _repo.getTemplates(includeInactive: true);
    if (!mounted) return;
    setState(() {
      switch (result) {
        case Ok(:final value):
          // Active first, as on the web; the API's order within each.
          _templates = [
            ...value.where((t) => t.isActive),
            ...value.where((t) => !t.isActive),
          ];
        case Err(:final error):
          _error = error.display;
      }
      _loading = false;
    });
  }

  /// The loaded list narrowed by the search text and the type chip.
  List<DiagnosticTemplateSummary> get _visible {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final t in _templates)
        if ((_type == null || t.type == _type) &&
            (query.isEmpty ||
                t.name.toLowerCase().contains(query) ||
                (t.description?.toLowerCase().contains(query) ?? false)))
          t,
    ];
  }

  Future<void> _create() async {
    await AppNav.push('${AppRoutes.diagnosticsTemplates}/new');
    if (mounted) await _load();
  }

  Future<void> _open(DiagnosticTemplateSummary template) async {
    await AppNav.push(
      '${AppRoutes.diagnosticsTemplates}/${Uri.encodeComponent(template.id)}',
    );
    if (mounted) await _load();
  }

  Future<void> _duplicate(DiagnosticTemplateSummary template) async {
    final result = await _repo.duplicateTemplate(template.id);
    if (!mounted) return;
    switch (result) {
      case Ok():
        messageComplete('"${template.name}" хуулагдлаа');
        await _load();
      case Err(:final error):
        messageError(error.display);
    }
  }

  Future<void> _delete(DiagnosticTemplateSummary template) async {
    final archives = (template.reportCount ?? 0) > 0;
    final ok = await ConfirmSheet.show(
      context,
      title: archives
          ? '"${template.name}" загварыг архивлах уу?'
          : '"${template.name}" загварыг устгах уу?',
      message: archives
          ? 'Бөглөгдсөн тайлантай тул устгахгүй, идэвхгүй болгож архивлана.'
          : 'Бөглөгдсөн тайлантай бол устгахгүй, идэвхгүй болгож архивлана.',
      confirmLabel: archives ? 'Архивлах' : 'Устгах',
      icon: archives ? Icons.archive_outlined : Icons.delete_outline_rounded,
      isDangerous: true,
    );
    if (!ok || !mounted) return;
    final result = await _repo.deleteTemplate(template.id);
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        messageComplete(
          value == TemplateDeleteOutcome.archived
              ? '"${template.name}" архивлагдлаа'
              : '"${template.name}" устгагдлаа',
        );
        await _load();
      case Err(:final error):
        messageError(error.display);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = CarserviceTheme.of(context);
    final user = _user;
    final canCreate = canSeeView(user, 'diagnostics.create');
    return Scaffold(
      backgroundColor: theme.shellBackground,
      appBar: AppBar(title: const Text('Оношилгоо')),
      floatingActionButton: canCreate && _templates.isNotEmpty
          ? FloatingActionButton.extended(
              key: const ValueKey('diagnostic_templates_add'),
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Нэмэх'),
            )
          : null,
      body: PermissionGate(
        permission: 'diagnostics.view',
        user: user,
        fallback: const EmptyState(
          message: 'Оношилгоо үзэх эрх хүрэлцэхгүй байна.',
          icon: Icons.lock_outline,
        ),
        child: _body(context, canCreate: canCreate),
      ),
    );
  }

  Widget _body(BuildContext context, {required bool canCreate}) {
    if (_loading) return const AppLoading();
    final error = _error;
    if (error != null) {
      return ErrorStateView(message: error, onRetry: _load);
    }
    if (_templates.isEmpty) {
      return _Empty(onCreate: canCreate ? _create : null);
    }
    final theme = CarserviceTheme.of(context);
    final visible = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Text(
            'Оношилгооны үйлчилгээний жагсаалт. Үнэ ба бүтэц тус бүрд '
            'тохируулна.',
            style: context.textStyles.caption.copyWith(color: theme.mutedText3),
          ),
        ),
        ListSearchBar(
          controller: _search,
          hintText: 'Нэр, тайлбараар хайх',
          onChanged: (_) => setState(() {}),
          onClear: () => setState(_search.clear),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            children: [
              for (final type in [null, ...DiagnosticType.selectable])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    key: ValueKey('diagnostic_templates_type_${type?.name}'),
                    label: Text(type?.label ?? 'Бүгд'),
                    selected: _type == type,
                    onSelected: (_) => setState(() => _type = type),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: visible.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 80),
                      EmptyState(
                        message: 'Хайлтад тохирох оношилгоо олдсонгүй',
                        icon: Icons.search_off_rounded,
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final template = visible[index];
                      return _TemplateCard(
                        template: template,
                        onOpen: () => _open(template),
                        onDuplicate: canCreate
                            ? () => _duplicate(template)
                            : null,
                        onDelete:
                            canSeeView(_user, 'diagnostics.delete') &&
                                !template.readOnly
                            ? () => _delete(template)
                            : null,
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onCreate});
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = CarserviceTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fact_check_outlined, size: 56, color: theme.mutedText3),
            const SizedBox(height: 16),
            Text(
              'Оношилгоо алга байна',
              style: context.textStyles.h3.copyWith(color: theme.ink),
            ),
            const SizedBox(height: 6),
            Text(
              'Машин хүлээж авах, үйлчилгээний дараах шалгалт зэрэгт '
              'зориулсан оношилгоо үүсгээрэй.',
              textAlign: TextAlign.center,
              style: context.textStyles.caption.copyWith(
                color: theme.mutedText3,
              ),
            ),
            if (onCreate != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey('diagnostic_templates_create_first'),
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Эхний оношилгоо үүсгэх'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One diagnostic service: the web table's row as a card.
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onOpen,
    required this.onDuplicate,
    required this.onDelete,
  });

  final DiagnosticTemplateSummary template;
  final VoidCallback onOpen;
  final VoidCallback? onDuplicate, onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = CarserviceTheme.of(context);
    final t = template;
    final price = t.price;
    final meta = TextStyle(
      fontFamily: theme.monoFontFamily,
      fontSize: 12,
      color: theme.mutedText2,
    );
    final radius = BorderRadius.circular(AppDimens.radiusMD);
    return Material(
      color: theme.panel,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: theme.border),
      ),
      child: InkWell(
        key: ValueKey('diagnostic_template_${t.id}'),
        borderRadius: radius,
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.bodyMedium.copyWith(
                            color: theme.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (t.description != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            t.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textStyles.caption.copyWith(
                              color: theme.mutedText3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _Actions(
                    readOnly: t.readOnly,
                    onOpen: onOpen,
                    onDuplicate: onDuplicate,
                    onDelete: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    TemplateChip(
                      label: t.type.label,
                      color: templateTypeColor(context, t.type),
                    ),
                    if (t.isSystemDefault)
                      TemplateChip(label: 'Системийн', color: theme.accent),
                    if (t.isShared)
                      TemplateChip(
                        label: 'Системийн сан',
                        color: theme.accentHi,
                      ),
                    if (t.categoryName != null)
                      TemplateChip(label: t.categoryName!),
                    TemplateChip(
                      label: t.isActive ? 'Идэвхтэй' : 'Идэвхгүй',
                      color: t.isActive ? theme.ok : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  if (price != null) Text(formatMoneyNum(price), style: meta),
                  if (t.durationMin != null)
                    Text('${t.durationMin}мин', style: meta),
                  Text('v${t.version}', style: meta),
                  if (t.reportCount != null)
                    Text('Хэрэглэсэн ${t.reportCount}', style: meta),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Action { open, duplicate, delete }

class _Actions extends StatelessWidget {
  const _Actions({
    required this.readOnly,
    required this.onOpen,
    required this.onDuplicate,
    required this.onDelete,
  });

  final bool readOnly;
  final VoidCallback onOpen;
  final VoidCallback? onDuplicate, onDelete;

  @override
  Widget build(BuildContext context) {
    final danger = CarserviceTheme.of(context).danger;
    // Compact, so a card without a description stays tight under its name.
    return PopupMenuButton<_Action>(
      tooltip: 'Үйлдэл',
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 32),
        fixedSize: const Size(40, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (action) => switch (action) {
        _Action.open => onOpen(),
        _Action.duplicate => onDuplicate?.call(),
        _Action.delete => onDelete?.call(),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _Action.open,
          child: ListTile(
            leading: Icon(
              readOnly ? Icons.visibility_outlined : Icons.edit_outlined,
            ),
            title: Text(readOnly ? 'Харах' : 'Засах'),
          ),
        ),
        if (onDuplicate != null)
          const PopupMenuItem(
            value: _Action.duplicate,
            child: ListTile(
              leading: Icon(Icons.copy_rounded),
              title: Text('Хуулах'),
            ),
          ),
        if (onDelete != null)
          PopupMenuItem(
            value: _Action.delete,
            child: ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: danger),
              title: Text('Устгах', style: TextStyle(color: danger)),
            ),
          ),
      ],
    );
  }
}
