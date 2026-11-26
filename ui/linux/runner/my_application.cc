#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include <desktop_multi_window/desktop_multi_window_plugin.h>

#include "flutter/generated_plugin_registrant.h"
#include "window_channel.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // A janela principal; nula antes de abrir e depois de fechada.
  GtkWindow* main_window;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// A janela só aparece quando o Flutter desenha o primeiro quadro.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// As janelas secundárias (Processos, decisão 51) rodam cada uma num motor
// próprio: os plugins e o canal da janela têm de ser registrados nele.
static void secondary_window_created_cb(FlPluginRegistry* registry) {
  fl_register_plugins(registry);
  egeon_window_channel_attach(registry);
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // Abrir o app de novo só traz para a frente o que já está aberto (como no
  // macOS): a segunda janela falaria com o mesmo core.
  if (self->main_window != nullptr) {
    gtk_window_present(self->main_window);
    return;
  }

  egeon_window_force_dark_theme();
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->main_window = window;
  g_object_add_weak_pointer(G_OBJECT(window),
                            reinterpret_cast<gpointer*>(&self->main_window));
  gtk_window_set_default_size(window, 1280, 720);
  // Abaixo disto a gaveta aberta ao lado no chat, os participantes e a
  // conversa não cabem; repete `RootLayout.minWindow`.
  GdkGeometry minimum = {};
  minimum.min_width = 1000;
  minimum.min_height = 600;
  gtk_window_set_geometry_hints(window, nullptr, &minimum, GDK_HINT_MIN_SIZE);

  // A janela principal fica com a decoração do sistema por enquanto; os
  // botões próprios (decisão 45) chegam depois.
  gtk_window_set_title(window, egeon_window_title());

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // O fundo do app (`carbon`): evita o clarão preto antes do primeiro quadro.
  gdk_rgba_parse(&background_color, "#1C2024");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // A view precisa estar realizada para o motor começar a desenhar.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  egeon_window_channel_attach(FL_PLUGIN_REGISTRY(view));
  desktop_multi_window_plugin_set_window_created_callback(
      secondary_window_created_cb);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // O primeiro argumento é o nome do binário.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Falha ao registrar o aplicativo: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // O nome do programa é o identificador: é por ele que o ambiente de
  // desktop liga o app em execução ao `.desktop`, já que o binário tem outro
  // nome.
  g_set_prgname(egeon_application_id());

  // Dev e estável têm identificadores diferentes e convivem; duas cópias do
  // mesmo identificador viram uma só. Com EGEON_HOME (teste, e2e, pasta
  // temporária) a cópia é isolada e nunca se funde com o app em uso: aí é
  // outra instância, que nem traz o outro para a frente.
#if GLIB_CHECK_VERSION(2, 74, 0)
  GApplicationFlags flags = G_APPLICATION_DEFAULT_FLAGS;
#else
  GApplicationFlags flags = G_APPLICATION_FLAGS_NONE;
#endif
  const gchar* isolated_home = g_getenv("EGEON_HOME");
  if (isolated_home != nullptr && isolated_home[0] != '\0') {
    flags = G_APPLICATION_NON_UNIQUE;
  }

  return MY_APPLICATION(g_object_new(
      my_application_get_type(), "application-id", egeon_application_id(),
      "flags", flags, nullptr));
}
