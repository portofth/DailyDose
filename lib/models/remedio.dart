import 'dart:convert';

class Remedio {
  final int id;
  final String nome;
  final String dose;
  final String hora; // "HH:mm"
  final int? dataSuspensao; // Timestamp (ms)
  final int? dataTermino;   // Timestamp (ms)
  
  // --- CAMPOS DE FREQUÊNCIA ---
  final int dataCriacao; 
  final String frequenciaTipo; // 'todos', 'semanal', 'intervalo'
  final List<int>? diasSemana; 
  final int? intervaloDias; 

  // --- TIPO DE MEDICAMENTO ---
  final String tipo; // 'geral' ou 'colirio'

  Remedio({
    required this.id,
    required this.nome,
    required this.dose,
    required this.hora,
    this.dataSuspensao,
    this.dataTermino,
    required this.dataCriacao, 
    this.frequenciaTipo = 'todos', 
    this.diasSemana,
    this.intervaloDias,
    this.tipo = 'geral', 
  });

  bool get isSuspenso {
    if (dataSuspensao == null) return false;
    final agora = DateTime.now();
    final dataFim = DateTime.fromMillisecondsSinceEpoch(dataSuspensao!);
    return dataFim.isAfter(agora);
  }

  bool get isFinalizado {
    if (dataTermino == null) return false;
    final agora = DateTime.now();
    final dt = DateTime.fromMillisecondsSinceEpoch(dataTermino!);
    final fimDoDiaTermino = DateTime(dt.year, dt.month, dt.day, 23, 59, 59);
    return agora.isAfter(fimDoDiaTermino);
  }

  // --- CONVERTE PARA SALVAR NO BANCO (SQL) ---
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'dose': dose,
      'hora': hora,
      'dataSuspensao': dataSuspensao,
      'dataTermino': dataTermino,
      'dataCriacao': dataCriacao,
      'frequenciaTipo': frequenciaTipo,
      // CONVERSÃO IMPORTANTE: Lista -> Texto
      'diasSemana': diasSemana != null ? jsonEncode(diasSemana) : null,
      'intervaloDias': intervaloDias,
      'tipo': tipo, 
    };
  }

  // --- LÊ DO BANCO PARA O APP ---
  factory Remedio.fromMap(Map<String, dynamic> map) {
    return Remedio(
      id: map['id'] ?? 0,
      nome: map['nome'] ?? '',
      dose: map['dose'] ?? '',
      hora: map['hora'] ?? '',
      dataSuspensao: map['dataSuspensao'],
      dataTermino: map['dataTermino'],
      dataCriacao: map['dataCriacao'] ?? DateTime.now().millisecondsSinceEpoch,
      frequenciaTipo: map['frequenciaTipo'] ?? 'todos',
      // CONVERSÃO IMPORTANTE: Texto -> Lista
      diasSemana: map['diasSemana'] != null 
          ? List<int>.from(jsonDecode(map['diasSemana'])) 
          : null,
      intervaloDias: map['intervaloDias'],
      tipo: map['tipo'] ?? 'geral', 
    );
  }

  String toJson() => json.encode(toMap());

  factory Remedio.fromJson(String source) => Remedio.fromMap(json.decode(source));
}