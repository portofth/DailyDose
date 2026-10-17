import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmeremedio/services/remedio_service.dart';

void main() {
  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final dbPath = join(await getDatabasesPath(), 'remedios_v13.db');
    await deleteDatabase(dbPath);
  });

  test('o banco inicia sem remédios pré-carregados', () async {
    final service = RemedioService();

    final remedios = await service.carregarRemedios();

    expect(remedios, isEmpty);
  });
}
