# Mantém as classes do plugin de notificação intactas
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Mantém o Gson (usado para salvar/ler dados internos) intacto
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn com.google.gson.**