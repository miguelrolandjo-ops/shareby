import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shareby/data/models.dart';
import 'package:shareby/ui/screens/home_screen.dart';

Folder folder(String id) => Folder(
      id: id,
      name: id,
      color: 0xFFE8A23D,
      emoji: '📁',
      isShared: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  final a = folder('a');
  final b = folder('b');
  final edited = <String>[];
  final drops = <String>[];

  Future<void> pump(WidgetTester tester) async {
    edited.clear();
    drops.clear();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          for (final f in [a, b])
            SizedBox(
              width: 150,
              height: 150,
              child: MovableFolderTile(
                key: ValueKey(f.id),
                folder: f,
                onEdit: (x) => edited.add(x.id),
                onDrop: (from, to) => drops.add('${from.id}>${to.id}'),
                child: Container(key: ValueKey('card-${f.id}'), color: Colors.amber),
              ),
            ),
        ]),
      ),
    ));
  }

  testWidgets('hold and release without moving opens Edit', (tester) async {
    await pump(tester);
    final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('card-a'))));
    await tester.pump(const Duration(milliseconds: 700));
    await g.up();
    await tester.pumpAndSettle();
    expect(edited, ['a']);
    expect(drops, isEmpty);
  });

  testWidgets('a wobble under 8 px still counts as holding still', (tester) async {
    await pump(tester);
    final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('card-a'))));
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveBy(const Offset(5, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(edited, ['a']);
  });

  testWidgets('dragging onto another folder moves it and does not open Edit', (tester) async {
    await pump(tester);
    final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('card-a'))));
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveTo(tester.getCenter(find.byKey(const ValueKey('card-b'))));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(drops, ['a>b']);
    expect(edited, isEmpty);
  });

  testWidgets('dragging and dropping on empty space does nothing', (tester) async {
    await pump(tester);
    final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('card-a'))));
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveBy(const Offset(0, 300));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(drops, isEmpty);
    expect(edited, isEmpty);
  });
}
