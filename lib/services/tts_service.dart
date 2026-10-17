import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts flutterTts = FlutterTts();

  Future<void> init() async {
    await flutterTts.setLanguage("pt-BR");
    
    // AUMENTADO: 0.5 é normal, 1.0 é bem rápido. 
    // 0.8 é um bom meio termo para idosos ouvirem com urgência mas clareza.
    await flutterTts.setSpeechRate(0.8); 
    
    await flutterTts.setPitch(1.0); // Tom natural
    await flutterTts.setVolume(1.0); // Volume máximo
    
    // Configuração importante para iOS (para o som sair mesmo no silencioso se possível)
    await flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.duckOthers
        ]
    );
  }

  Future<void> falar(String texto) async {
    await flutterTts.speak(texto);
  }

  Future<void> parar() async {
    await flutterTts.stop();
  }
  
  // Verifica se está falando para não encavalar o loop
  Future<bool> estaFalando() async {
    // Nota: nem todos os SOs retornam isso corretamente, mas ajuda a controlar
    return false; // Simplificado para garantir que o loop controle o tempo
  }
}