#include "window_channel.h"

#include <gtk/gtk.h>

#include <cstring>

namespace {

constexpr char kChannelName[] = "egeon/window";

// A janela que contém a view. Nula enquanto a view não foi posta numa janela.
GtkWindow* window_of(GtkWidget* view) {
  GtkWidget* top = gtk_widget_get_toplevel(view);
  return GTK_IS_WINDOW(top) ? GTK_WINDOW(top) : nullptr;
}

// Os argumentos do Dart chegam como int ou como double conforme o valor.
bool read_number(FlValue* args, const char* key, double* out) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return false;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr) return false;
  switch (fl_value_get_type(value)) {
    case FL_VALUE_TYPE_INT:
      *out = static_cast<double>(fl_value_get_int(value));
      return true;
    case FL_VALUE_TYPE_FLOAT:
      *out = fl_value_get_float(value);
      return true;
    default:
      return false;
  }
}

const gchar* read_string(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

// O dev é o que `EGEON_FLAVOR=dev` ou um build que não é release pedem (o
// `.dev` já vem no APPLICATION_ID, pelo CMake): a mesma regra do EgeonFlavor.
bool is_dev_flavor() {
  return g_str_has_suffix(APPLICATION_ID, ".dev") ||
         g_strcmp0(g_getenv("EGEON_FLAVOR"), "dev") == 0;
}

// Onde a posição das janelas fica guardada: uma pasta por cópia do app, como o
// NSUserDefaults do macOS separa o estável do dev pelo identificador do
// bundle.
gchar* state_file() {
  g_autofree gchar* folder =
      g_build_filename(g_get_user_state_dir(), egeon_application_id(), nullptr);
  g_mkdir_with_parents(folder, 0700);
  return g_build_filename(folder, "windows.ini", nullptr);
}

void save_frame(GtkWindow* window, const gchar* autosave) {
  g_autofree gchar* path = state_file();
  g_autoptr(GKeyFile) file = g_key_file_new();
  // Um arquivo ausente ou ilegível só recomeça do zero.
  g_key_file_load_from_file(file, path, G_KEY_FILE_NONE, nullptr);
  gint x = 0, y = 0, width = 0, height = 0;
  gtk_window_get_position(window, &x, &y);
  gtk_window_get_size(window, &width, &height);
  g_key_file_set_integer(file, autosave, "x", x);
  g_key_file_set_integer(file, autosave, "y", y);
  g_key_file_set_integer(file, autosave, "width", width);
  g_key_file_set_integer(file, autosave, "height", height);
  g_key_file_save_to_file(file, path, nullptr);
}

// Reabre onde estava; a primeira vez (sem nada guardado) devolve falso e a
// janela fica no centro.
bool restore_frame(GtkWindow* window, const gchar* autosave, gint min_width,
                   gint min_height) {
  g_autofree gchar* path = state_file();
  g_autoptr(GKeyFile) file = g_key_file_new();
  if (!g_key_file_load_from_file(file, path, G_KEY_FILE_NONE, nullptr)) {
    return false;
  }
  GError* error = nullptr;
  gint x = g_key_file_get_integer(file, autosave, "x", &error);
  if (error != nullptr) {
    g_error_free(error);
    return false;
  }
  gint y = g_key_file_get_integer(file, autosave, "y", nullptr);
  gint width = g_key_file_get_integer(file, autosave, "width", nullptr);
  gint height = g_key_file_get_integer(file, autosave, "height", nullptr);
  if (width < min_width || height < min_height) return false;
  gtk_window_resize(window, width, height);
  gtk_window_move(window, x, y);
  return true;
}

// Só destrói se continuar escondida: reaberta nesse meio tempo (o Dart acha
// a janela na lista do plugin e a mostra de novo), ela fica.
gboolean destroy_later(gpointer window) {
  if (!gtk_widget_get_visible(GTK_WIDGET(window))) {
    gtk_widget_destroy(GTK_WIDGET(window));
  }
  g_object_unref(window);
  return G_SOURCE_REMOVE;
}

// Fechar uma janela secundária destrói a view Flutter dela de uma vez, e o
// GLX derruba o app inteiro (BadAccess ao trocar o contexto da thread de
// raster): esconde primeiro e destrói quando o motor já largou a superfície.
void close_secondary(GtkWindow* window) {
  const gchar* autosave = static_cast<const gchar*>(
      g_object_get_data(G_OBJECT(window), "egeon-autosave"));
  if (autosave != nullptr) save_frame(window, autosave);
  gtk_widget_hide(GTK_WIDGET(window));
  g_timeout_add(500, destroy_later, g_object_ref(window));
}

gboolean save_after_move(gpointer window) {
  g_object_set_data(G_OBJECT(window), "egeon-save-source", nullptr);
  const gchar* autosave = static_cast<const gchar*>(
      g_object_get_data(G_OBJECT(window), "egeon-autosave"));
  if (autosave != nullptr && gtk_widget_get_mapped(GTK_WIDGET(window))) {
    save_frame(GTK_WINDOW(window), autosave);
  }
  return G_SOURCE_REMOVE;
}

// O autosave do macOS grava a cada movimento e a cada resize; aqui o evento
// de configuração vem em rajada durante o arrasto, então grava 300 ms depois
// do último. A referência segura a janela até o temporizador disparar ou ser
// refeito.
gboolean on_configure_event(GtkWidget* widget, GdkEventConfigure*, gpointer) {
  const guint pending = GPOINTER_TO_UINT(
      g_object_get_data(G_OBJECT(widget), "egeon-save-source"));
  if (pending != 0) g_source_remove(pending);
  const guint source =
      g_timeout_add_full(G_PRIORITY_DEFAULT, 300, save_after_move,
                         g_object_ref(widget), g_object_unref);
  g_object_set_data(G_OBJECT(widget), "egeon-save-source",
                    GUINT_TO_POINTER(source));
  return FALSE;
}

gboolean on_delete_event(GtkWidget* widget, GdkEvent*, gpointer) {
  close_secondary(GTK_WINDOW(widget));
  return TRUE;
}

bool present(GtkWindow* window, FlValue* args) {
  const gchar* title = read_string(args, "title");
  const gchar* autosave = read_string(args, "autosave");
  double width = 0, height = 0, min_width = 0, min_height = 0;
  if (title == nullptr || autosave == nullptr ||
      !read_number(args, "width", &width) ||
      !read_number(args, "height", &height) ||
      !read_number(args, "minWidth", &min_width) ||
      !read_number(args, "minHeight", &min_height)) {
    return false;
  }

  gtk_window_set_title(window, title);
  GdkGeometry minimum = {};
  minimum.min_width = static_cast<gint>(min_width);
  minimum.min_height = static_cast<gint>(min_height);
  gtk_window_set_geometry_hints(window, nullptr, &minimum, GDK_HINT_MIN_SIZE);
  gtk_window_resize(window, static_cast<gint>(width),
                    static_cast<gint>(height));
  gtk_window_set_position(window, GTK_WIN_POS_CENTER);

  if (restore_frame(window, autosave, minimum.min_width, minimum.min_height)) {
    gtk_window_set_position(window, GTK_WIN_POS_NONE);
  }
  // O nome vai na própria janela para a segunda abertura não ligar os sinais
  // de novo.
  if (g_object_get_data(G_OBJECT(window), "egeon-autosave") == nullptr) {
    g_signal_connect(window, "delete-event", G_CALLBACK(on_delete_event),
                     nullptr);
    g_signal_connect(window, "configure-event",
                     G_CALLBACK(on_configure_event), nullptr);
  }
  g_object_set_data_full(G_OBJECT(window), "egeon-autosave", g_strdup(autosave),
                         g_free);
  gtk_window_present(window);
  return true;
}

FlMethodResponse* frame_of(GtkWidget* view) {
  GdkWindow* gdk_window = gtk_widget_get_window(view);
  if (gdk_window == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  // Em X11 a origem é a da tela; no Wayland o compositor não a informa e
  // vem 0,0 — o /geometry só vale com X11.
  gint x = 0, y = 0;
  gdk_window_get_origin(gdk_window, &x, &y);
  gint screen_height = 0;
  GdkMonitor* monitor = gdk_display_get_monitor_at_window(
      gdk_window_get_display(gdk_window), gdk_window);
  if (monitor != nullptr) {
    GdkRectangle area;
    gdk_monitor_get_geometry(monitor, &area);
    screen_height = area.height;
  }
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "x", fl_value_new_float(x));
  fl_value_set_string_take(map, "y", fl_value_new_float(y));
  fl_value_set_string_take(
      map, "width", fl_value_new_float(gtk_widget_get_allocated_width(view)));
  fl_value_set_string_take(
      map, "height",
      fl_value_new_float(gtk_widget_get_allocated_height(view)));
  fl_value_set_string_take(map, "screenHeight",
                           fl_value_new_float(screen_height));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(map));
}

void on_method_call(FlMethodChannel*, FlMethodCall* call, gpointer user_data) {
  GtkWidget* view = GTK_WIDGET(user_data);
  GtkWindow* window = window_of(view);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);

  g_autoptr(FlMethodResponse) response = nullptr;
  if (window == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "activate") == 0) {
    // Clique numa notificação: traz o app, mesmo minimizado.
    gtk_window_deiconify(window);
    gtk_window_present(window);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "frame") == 0) {
    response = frame_of(view);
  } else if (strcmp(method, "present") == 0) {
    response = present(window, args)
                   ? FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr))
                   : FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  } else if (strcmp(method, "close") == 0) {
    close_secondary(window);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

}  // namespace

void egeon_window_channel_attach(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "EgeonWindow");
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), kChannelName,
      FL_METHOD_CODEC(codec));
  // O registro é a própria view: o canal fica pendurado nela e cai junto, e
  // por isso o ponteiro que o handler guarda nunca sobrevive à view.
  fl_method_channel_set_method_call_handler(channel, on_method_call, registry,
                                            nullptr);
  g_object_set_data_full(G_OBJECT(registry), "egeon-window-channel", channel,
                         g_object_unref);
}

const char* egeon_application_id() {
  static const gchar* id = nullptr;
  if (id == nullptr) {
    id = (is_dev_flavor() && !g_str_has_suffix(APPLICATION_ID, ".dev"))
             ? g_strconcat(APPLICATION_ID, ".dev", nullptr)
             : APPLICATION_ID;
  }
  return id;
}

const char* egeon_window_title() {
  return is_dev_flavor() ? "Egeon Deck (dev)" : "Egeon Deck";
}

void egeon_window_force_dark_theme() {
  GtkSettings* settings = gtk_settings_get_default();
  if (settings != nullptr) {
    g_object_set(settings, "gtk-application-prefer-dark-theme", TRUE, nullptr);
  }
}
