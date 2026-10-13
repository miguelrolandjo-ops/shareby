import 'package:flutter_test/flutter_test.dart';
import 'package:shareby/data/refactor_undo.dart';

void main() {
  RefactorUndo sample(DateTime at) => RefactorUndo(
        at: at,
        items: const [
          ItemBefore(id: 'i1', folderId: 'f1', status: 'confirmed', tag: 'Dance'),
          ItemBefore(id: 'i2', folderId: null, status: 'new', tag: null),
        ],
        createdFolderIds: const ['n1'],
        removedFolderIds: const ['f1'],
      );

  test('survives a round trip through JSON', () {
    final back = RefactorUndo.fromJson(sample(DateTime.utc(2026, 10, 13)).toJson());
    expect(back.linkCount, 2);
    expect(back.items.first.tag, 'Dance');
    expect(back.items.last.folderId, isNull);
    expect(back.createdFolderIds, ['n1']);
    expect(back.removedFolderIds, ['f1']);
  });

  test('can be undone for 24 hours, then it expires', () {
    final at = DateTime(2026, 10, 13, 9);
    expect(sample(at).isExpired(at.add(const Duration(hours: 23, minutes: 59))), isFalse);
    expect(sample(at).isExpired(at.add(const Duration(hours: 24, minutes: 1))), isTrue);
  });
}
