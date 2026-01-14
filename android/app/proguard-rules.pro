# MediaPipe
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Protocol Buffers
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# RAG functionality
-keep class com.google.ai.edge.localagents.** { *; }
-dontwarn com.google.ai.edge.localagents.**
# Please add these rules to your existing keep rules in order to suppress warnings.
# This is generated automatically by the Android Gradle plugin.
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate

-keep class com.unity3d.player.** { *; }
-dontwarn com.unity3d.player.**
