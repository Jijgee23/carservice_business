import 'package:carservice_business/core/utils/result.dart';
import 'package:carservice_business/features/diagnostics/domain/diagnostic.dart';
import 'package:carservice_business/features/diagnostics/domain/diagnostics_repository.dart';
import 'package:carservice_business/features/diagnostics/presentation/controllers/new_inspection_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _TemplateRepository implements DiagnosticTemplateRepository {
  _TemplateRepository({this.template = _defaultTemplate});
  final DiagnosticTemplateDetail template;

  static const _defaultTemplate = DiagnosticTemplateDetail(
    id: 'template-1',
    name: 'Inspection',
    type: DiagnosticType.INTAKE,
    version: 1,
    isActive: true,
    isSystemDefault: false,
    schema: TemplateSchema(
      sections: [
        TemplateSection(
          id: 'section-1',
          title: 'Checks',
          items: [
            TemplateItem(
              id: 'gate',
              label: 'Gate',
              type: ItemType.check,
              required: true,
              options: ['Yes', 'No'],
            ),
            TemplateItem(
              id: 'conditional',
              label: 'Conditional',
              type: ItemType.text,
              required: false,
              showWhen: ShowWhen(itemId: 'gate', values: ['Yes']),
            ),
            TemplateItem(
              id: 'positioned',
              label: 'Positioned',
              type: ItemType.check,
              required: false,
              positionSet: PositionSetKey.LR,
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Future<Result<List<DiagnosticTemplateSummary>>> getTemplates({
    bool includeInactive = false,
  }) async => Ok([template]);
  @override
  Future<Result<DiagnosticTemplateDetail>> getTemplate(String id) async =>
      Ok(template);
  @override
  Future<Result<DiagnosticTemplateSummary>> createTemplate(
    Map<String, dynamic> body,
  ) => throw UnimplementedError();
  @override
  Future<Result<DiagnosticTemplateSummary>> updateTemplate(
    String id,
    Map<String, dynamic> body,
  ) => throw UnimplementedError();
  @override
  Future<Result<TemplateDeleteOutcome>> deleteTemplate(String id) =>
      throw UnimplementedError();
  @override
  Future<Result<DiagnosticTemplateSummary>> duplicateTemplate(String id) =>
      throw UnimplementedError();
}

void main() {
  test(
    'typed template preserves showWhen and positionSet in the fill model',
    () async {
      final controller = NewInspectionController(repo: _TemplateRepository());
      addTearDown(controller.dispose);

      await controller.selectTemplate('template-1');
      final items = controller.sections.single.items;
      final conditional = items.firstWhere((item) => item.id == 'conditional');
      final positioned = items.firstWhere((item) => item.id == 'positioned');

      expect(controller.isItemVisible(conditional), isFalse);
      controller.setAnswer('gate', 'Yes');
      expect(controller.isItemVisible(conditional), isTrue);
      expect(positioned.positionSet?.name, PositionSetKey.LR.name);
      expect(
        positioned.positionSet!.positions.map((position) => position.code),
        ['L', 'R'],
      );
    },
  );

  test(
    'markAll without scope marks every section; scoped stays scoped',
    () async {
      const item = TemplateItem(
        id: 'a',
        label: 'A',
        type: ItemType.check,
        required: false,
        options: ['Хэвийн', 'Анхаарах'],
      );
      const item2 = TemplateItem(
        id: 'b',
        label: 'B',
        type: ItemType.check,
        required: false,
        options: ['Хэвийн', 'Анхаарах'],
      );
      const item3 = TemplateItem(
        id: 'c',
        label: 'C',
        type: ItemType.check,
        required: false,
        options: ['Yes', 'No'],
      );
      final controller = NewInspectionController(
        repo: _TemplateRepository(
          template: const DiagnosticTemplateDetail(
            id: 'template-1',
            name: 'Inspection',
            type: DiagnosticType.INTAKE,
            version: 1,
            isActive: true,
            isSystemDefault: false,
            schema: TemplateSchema(
              sections: [
                TemplateSection(id: 's1', title: 'One', items: [item]),
                TemplateSection(id: 's2', title: 'Two', items: [item2, item3]),
              ],
            ),
          ),
        ),
      );
      addTearDown(controller.dispose);
      await controller.selectTemplate('template-1');

      controller.markAll('Хэвийн', [controller.sections.first]);
      expect(controller.getAnswer('a'), 'Хэвийн');
      expect(controller.getAnswer('b'), isNull);

      controller.markAll('Анхаарах');
      expect(controller.getAnswer('a'), 'Анхаарах');
      expect(controller.getAnswer('b'), 'Анхаарах');
      expect(controller.getAnswer('c'), isNull);
    },
  );
}
