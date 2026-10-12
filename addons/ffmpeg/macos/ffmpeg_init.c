#include "gdextension_interface.h"
#include <stddef.h>

static void initialize_ffmpeg_module(void *p_userdata, GDExtensionInitializationLevel p_level) {
	(void)p_userdata;
	(void)p_level;
}

static void deinitialize_ffmpeg_module(void *p_userdata, GDExtensionInitializationLevel p_level) {
	(void)p_userdata;
	(void)p_level;
}

GDExtensionBool ffmpeg_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	(void)p_get_proc_address;
	(void)p_library;
	r_initialization->initialize = initialize_ffmpeg_module;
	r_initialization->deinitialize = deinitialize_ffmpeg_module;
	r_initialization->userdata = NULL;
	r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	return 1;
}
