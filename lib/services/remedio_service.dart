import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/remedio.dart';
import 'package:intl/intl.dart';

class RemedioService {
  static final RemedioService _instance = RemedioService._internal();
  factory RemedioService() => _instance;
  RemedioService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // Banco vazio por padrão: o usuário cadastra os remédios manualmente.
    String path = join(await getDatabasesPath(), 'remedios_v13.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE remedios(
            id INTEGER PRIMARY KEY,
            nome TEXT,
            dose TEXT,
            hora TEXT,
            dataSuspensao INTEGER,
            dataTermino INTEGER,
            dataCriacao INTEGER,
            frequenciaTipo TEXT,
            diasSemana TEXT,
            intervaloDias INTEGER,
            tipo TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE historico(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            hora TEXT,
            data TEXT
          )
        ''');
      },
    );
  }

  // --- CRUD GERAL ---
  Future<void> salvarLista(List<Remedio> lista) async {
    final db = await database;
    Batch batch = db.batch();

    List<Map> maps = await db.query('remedios', columns: ['id']);
    List<int> idsNoBanco = maps.map((e) => e['id'] as int).toList();
    List<int> idsNaLista = lista.map((e) => e.id).toList();

    for (int id in idsNoBanco) {
      if (!idsNaLista.contains(id)) {
        batch.delete('remedios', where: 'id = ?', whereArgs: [id]);
      }
    }

    for (var remedio in lista) {
      batch.insert(
        'remedios',
        remedio.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Remedio>> carregarRemedios() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('remedios');
    return List.generate(maps.length, (i) => Remedio.fromMap(maps[i]));
  }

  Future<List<Remedio>> pegarRemediosDoHorario(String hora) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'remedios',
      where: 'hora = ?',
      whereArgs: [hora],
    );

    List<Remedio> todos = List.generate(
      maps.length,
      (i) => Remedio.fromMap(maps[i]),
    );
    final agora = DateTime.now();
    return todos
        .where(
          (r) =>
              !r.isSuspenso && !r.isFinalizado && deveTomarNestaData(r, agora),
        )
        .toList();
  }

  // --- NOVO MÉTODO PARA BACKGROUND (CALCULA O FUTURO) ---
  Future<int?> calcularProximoIntervaloSegundos(String hora) async {
    final db = await database;
    // Pega TODOS os remédios deste horário, sem filtrar data ainda
    final List<Map<String, dynamic>> maps = await db.query(
      'remedios',
      where: 'hora = ?',
      whereArgs: [hora],
    );

    if (maps.isEmpty) return null;

    List<Remedio> remedios = List.generate(
      maps.length,
      (i) => Remedio.fromMap(maps[i]),
    );
    // Remove os que estão suspensos/finalizados
    remedios = remedios.where((r) => !r.isSuspenso && !r.isFinalizado).toList();

    if (remedios.isEmpty) return null;

    final agora = DateTime.now();
    final partes = hora.split(':');
    final h = int.parse(partes[0]);
    final m = int.parse(partes[1]);

    // Começa a procurar a partir de AMANHÃ (dia + 1), pois o alarme de hoje já tocou
    for (int i = 1; i <= 31; i++) {
      final dataTeste = agora.add(Duration(days: i));
      final dataAlvo = DateTime(
        dataTeste.year,
        dataTeste.month,
        dataTeste.day,
        h,
        m,
        0,
      );

      // Verifica se algum remédio desse horário deve ser tomado nessa data futura
      bool temRemedio = remedios.any((r) => deveTomarNestaData(r, dataTeste));

      if (temRemedio) {
        // Retorna quantos segundos faltam até lá
        return dataAlvo.difference(agora).inSeconds;
      }
    }
    return null; // Nada encontrado nos próximos 30 dias
  }

  // --- LÓGICA DE FREQUÊNCIA ---
  bool deveTomarNestaData(Remedio r, DateTime data) {
    if (r.frequenciaTipo == 'todos') return true;

    if (r.frequenciaTipo == 'semanal') {
      if (r.diasSemana == null || r.diasSemana!.isEmpty) return true;
      return r.diasSemana!.contains(data.weekday);
    }

    if (r.frequenciaTipo == 'intervalo') {
      if (r.intervaloDias == null || r.intervaloDias! < 2) return true;
      final dataCriacao = DateTime.fromMillisecondsSinceEpoch(r.dataCriacao);
      final d1 = DateTime(dataCriacao.year, dataCriacao.month, dataCriacao.day);
      final d2 = DateTime(data.year, data.month, data.day);
      final diferenca = d2.difference(d1).inDays;
      return (diferenca % r.intervaloDias!) == 0;
    }
    return true;
  }

  Future<bool> jaTomouHoje(String hora) async {
    final db = await database;
    final hoje = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final List<Map<String, dynamic>> maps = await db.query(
      'historico',
      where: 'hora = ? AND data = ?',
      whereArgs: [hora, hoje],
    );
    return maps.isNotEmpty;
  }

  Future<void> marcarComoTomadoHoje(String hora) async {
    final db = await database;
    final hoje = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await db.insert('historico', {'hora': hora, 'data': hoje});
  }
}
