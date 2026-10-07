import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeplay/api/jellyfin.dart';
import 'package:homeplay/services/appearance.dart';
import 'package:homeplay/widgets/library_tiles.dart';

final _libraries = [
  JellyfinItem({'Id': 'm', 'Name': 'Фильмы', 'CollectionType': 'movies', 'IsFolder': true}),
  JellyfinItem({'Id': 'p', 'Name': 'Фото с телефона', 'CollectionType': 'homevideos', 'IsFolder': true}),
  JellyfinItem({'Id': 'a', 'Name': 'Музыка', 'CollectionType': 'music', 'IsFolder': true}),
  JellyfinItem({'Id': 's', 'Name': 'Сериалы', 'CollectionType': 'tvshows', 'IsFolder': true}),
];

void main() {
  for (final layout in LibraryLayout.values) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('${layout.name} fits a phone screen at text size $scale', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.625;
        addTearDown(tester.view.reset);
        JellyfinItem? opened;
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery.withClampedTextScaling(
            minScaleFactor: scale,
            maxScaleFactor: scale,
            child: Scaffold(
              body: ListView(children: [
                LibrariesView(
                  layout: layout,
                  libraries: _libraries,
                  counts: const {'m': '4 movies', 'p': '12 files', 'a': '26 tracks', 's': '1 show'},
                  onOpen: (l) => opened = l,
                ),
              ]),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        expect(find.text('Музыка'), findsOneWidget);
        expect(find.text('26 tracks'), findsOneWidget);
        await tester.tap(find.text('Сериалы'));
        expect(opened?.id, 's');
      });
    }
  }
}
