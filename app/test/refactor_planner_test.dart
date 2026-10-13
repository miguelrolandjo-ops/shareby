import 'package:flutter_test/flutter_test.dart';
import 'package:shareby/data/models.dart';
import 'package:shareby/data/refactor_planner.dart';

Item item(String id, String title) => Item(
      id: id,
      url: 'https://example.com/$id',
      title: title,
      source: 'web',
      status: 'confirmed',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Item inFolder(String id, String title, String folderId) => Item(
      id: id,
      folderId: folderId,
      url: 'https://example.com/$id',
      title: title,
      source: 'web',
      status: 'confirmed',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  const planner = RefactorPlanner();
  final items = [
    item('1', 'NewJeans Hype Boy fancam'),
    item('2', 'Resep ayam geprek pedas'),
    item('3', 'Best latte in Canggu cafe'),
    item('4', 'xyz qrs'),
  ];

  RefactorGroup? group(RefactorPlan p, String name) =>
      p.groups.where((g) => g.name.toLowerCase() == name.toLowerCase()).firstOrNull;

  test('AI proposes broad groups for everything', () {
    final plan = planner.plan(items);
    expect(group(plan, 'K-Pop')?.itemIds, ['1']);
    expect(group(plan, 'Recipes')?.itemIds, ['2']);
    expect(group(plan, 'Cafes')?.itemIds, ['3']);
    expect(plan.unassigned, isEmpty);
  });

  test('a user group comes first and claims the links that fit it', () {
    final plan = planner.plan(items, seeds: [const RefactorSeed('Music')]);
    expect(plan.groups.first.name, 'Music');
    expect(plan.groups.first.fromUser, isTrue);
    expect(plan.groups.first.itemIds, contains('1'));
    expect(group(plan, 'K-Pop'), isNull);
  });

  test('using only my groups leaves the rest where they are', () {
    final plan = planner.plan(items, seeds: [const RefactorSeed('Music')], proposeRest: false);
    expect(plan.groups.map((g) => g.name), ['Music']);
    expect(plan.unassigned.toSet(), {'2', '3', '4'});
  });

  test('duplicate seed names are collapsed', () {
    final plan =
        planner.plan(items, seeds: [const RefactorSeed('Music'), const RefactorSeed('music '), const RefactorSeed('')]);
    expect(plan.groups.where((g) => g.fromUser).length, 1);
  });

  test('a kept folder holds on to its links; an unchecked one is regrouped', () {
    final mixed = [
      inFolder('a', 'xyz qrs', 'f-keep'), // fits nothing, but lives in a kept folder
      inFolder('b', 'Best latte in Canggu cafe', 'f-drop'), // its folder is not kept
    ];
    final plan = planner.plan(mixed, seeds: [const RefactorSeed('Misc', existingFolderId: 'f-keep')]);
    expect(group(plan, 'Misc')?.itemIds, ['a']);
    expect(group(plan, 'Misc')?.existing, isTrue);
    expect(group(plan, 'Cafes')?.itemIds, ['b']);
  });
}
