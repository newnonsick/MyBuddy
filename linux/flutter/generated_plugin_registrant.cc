//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_gemma/flutter_gemma_plugin.h>
#include <flutter_timezone/flutter_timezone_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) flutter_gemma_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterGemmaPlugin");
  flutter_gemma_plugin_register_with_registrar(flutter_gemma_registrar);
  g_autoptr(FlPluginRegistrar) flutter_timezone_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterTimezonePlugin");
  flutter_timezone_plugin_register_with_registrar(flutter_timezone_registrar);
}
