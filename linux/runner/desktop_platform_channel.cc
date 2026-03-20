#include "desktop_platform_channel.h"

#include <errno.h>
#include <glib.h>
#include <glib/gstdio.h>
#include <limits.h>
#include <unistd.h>

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <memory>
#include <optional>
#include <regex>
#include <sstream>
#include <string>
#include <vector>

struct _DesktopPlatformChannel {
  MyApplication* application;
  GtkWindow* window;
  FlView* view;
  FlMethodChannel* channel;
  GtkStatusIcon* status_icon;
  GtkWidget* menu;
  std::string preferred_mode = "proxy";
  std::string vpn_connection_name = "XWorkmate Tunnel";
  std::string proxy_host = "127.0.0.1";
  int proxy_port = 7890;
  bool tray_enabled = true;
  bool tray_available = true;
  bool autostart_enabled = false;
  bool network_manager_available = false;
  std::string desktop_environment = "unknown";
  std::string status_message;
};

namespace {

constexpr char kChannelName[] = "plus.svc.xworkmate/desktop_platform";
constexpr char kDesktopFileId[] = "plus.svc.xworkmate.desktop";

struct CommandResult {
  bool ok = false;
  int exit_status = -1;
  std::string stdout_text;
  std::string stderr_text;
};

std::string json_escape(const std::string& input) {
  std::ostringstream escaped;
  for (const char ch : input) {
    switch (ch) {
      case '\\':
        escaped << "\\\\";
        break;
      case '"':
        escaped << "\\\"";
        break;
      case '\n':
        escaped << "\\n";
        break;
      default:
        escaped << ch;
        break;
    }
  }
  return escaped.str();
}

std::string trim_quotes(const std::string& value) {
  if (value.size() >= 2 && value.front() == '"' && value.back() == '"') {
    return value.substr(1, value.size() - 2);
  }
  return value;
}

std::optional<std::string> json_string(const std::string& payload,
                                       const std::string& key) {
  const std::regex pattern("\"" + key + "\"\\s*:\\s*\"((?:\\\\.|[^\"])*)\"");
  std::smatch match;
  if (!std::regex_search(payload, match, pattern) || match.size() < 2) {
    return std::nullopt;
  }
  std::string value = match[1].str();
  value = std::regex_replace(value, std::regex("\\\\\""), "\"");
  value = std::regex_replace(value, std::regex("\\\\\\\\"), "\\");
  return value;
}

std::optional<int> json_int(const std::string& payload, const std::string& key) {
  const std::regex pattern("\"" + key + "\"\\s*:\\s*(\\d+)");
  std::smatch match;
  if (!std::regex_search(payload, match, pattern) || match.size() < 2) {
    return std::nullopt;
  }
  return std::stoi(match[1].str());
}

std::optional<bool> json_bool(const std::string& payload,
                              const std::string& key) {
  const std::regex pattern("\"" + key + "\"\\s*:\\s*(true|false)");
  std::smatch match;
  if (!std::regex_search(payload, match, pattern) || match.size() < 2) {
    return std::nullopt;
  }
  return match[1].str() == "true";
}

CommandResult run_command(const std::vector<std::string>& args) {
  std::vector<std::unique_ptr<gchar, decltype(&g_free)>> quoted;
  quoted.reserve(args.size());
  std::ostringstream command;
  for (size_t index = 0; index < args.size(); index++) {
    if (index > 0) {
      command << ' ';
    }
    quoted.emplace_back(g_shell_quote(args[index].c_str()), g_free);
    command << quoted.back().get();
  }

  gchar* stdout_text = nullptr;
  gchar* stderr_text = nullptr;
  gint exit_status = -1;
  GError* error = nullptr;
  const gboolean ok = g_spawn_command_line_sync(command.str().c_str(),
                                                &stdout_text, &stderr_text,
                                                &exit_status, &error);
  CommandResult result;
  result.ok = ok && error == nullptr;
  result.exit_status = exit_status;
  if (stdout_text != nullptr) {
    result.stdout_text = stdout_text;
  }
  if (stderr_text != nullptr) {
    result.stderr_text = stderr_text;
  }
  if (error != nullptr) {
    result.stderr_text = error->message;
    g_error_free(error);
  }
  g_free(stdout_text);
  g_free(stderr_text);
  return result;
}

bool command_succeeds(const std::vector<std::string>& args) {
  const CommandResult result = run_command(args);
  return result.ok && result.exit_status == 0;
}

std::string detect_desktop_environment() {
  const char* current = g_getenv("XDG_CURRENT_DESKTOP");
  const std::string desktop = current == nullptr ? "" : current;
  std::unique_ptr<gchar, decltype(&g_free)> lowered_raw(
      g_ascii_strdown(desktop.c_str(), -1), g_free);
  const std::string lowered =
      lowered_raw == nullptr ? std::string() : lowered_raw.get();
  if (lowered.find("gnome") != std::string::npos) {
    return "gnome";
  }
  if (lowered.find("kde") != std::string::npos ||
      lowered.find("plasma") != std::string::npos) {
    return "kde";
  }
  if (g_getenv("KDE_FULL_SESSION") != nullptr) {
    return "kde";
  }
  return "unknown";
}

std::string autostart_path() {
  const char* config_home = g_get_user_config_dir();
  std::ostringstream path;
  path << config_home << "/autostart/" << kDesktopFileId;
  return path.str();
}

std::string executable_path() {
  gchar buffer[PATH_MAX];
  const ssize_t size = readlink("/proc/self/exe", buffer, sizeof(buffer) - 1);
  if (size <= 0) {
    return "xworkmate";
  }
  buffer[size] = '\0';
  return buffer;
}

bool write_autostart_file() {
  const std::string path = autostart_path();
  const std::string directory = path.substr(0, path.find_last_of('/'));
  if (g_mkdir_with_parents(directory.c_str(), 0755) != 0) {
    return false;
  }
  std::ostringstream contents;
  contents << "[Desktop Entry]\n";
  contents << "Type=Application\n";
  contents << "Version=1.0\n";
  contents << "Name=XWorkmate\n";
  contents << "Exec=" << executable_path() << "\n";
  contents << "Icon=xworkmate\n";
  contents << "Terminal=false\n";
  contents << "Categories=Network;Utility;\n";
  contents << "StartupNotify=true\n";
  return g_file_set_contents(path.c_str(), contents.str().c_str(), -1,
                             nullptr);
}

bool remove_autostart_file() {
  return g_remove(autostart_path().c_str()) == 0 || errno == ENOENT;
}

bool autostart_enabled() {
  return g_file_test(autostart_path().c_str(), G_FILE_TEST_EXISTS);
}

bool network_manager_available() {
  return command_succeeds({"nmcli", "--version"});
}

bool tunnel_profile_exists(const std::string& connection_name) {
  const CommandResult result = run_command(
      {"nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"});
  if (!result.ok || result.exit_status != 0) {
    return false;
  }
  std::istringstream lines(result.stdout_text);
  std::string line;
  while (std::getline(lines, line)) {
    if (line.rfind(connection_name + ":", 0) == 0) {
      return true;
    }
  }
  return false;
}

bool tunnel_connected(const std::string& connection_name) {
  const CommandResult result = run_command(
      {"nmcli", "-t", "-f", "NAME", "connection", "show", "--active"});
  if (!result.ok || result.exit_status != 0) {
    return false;
  }
  std::istringstream lines(result.stdout_text);
  std::string line;
  while (std::getline(lines, line)) {
    if (line == connection_name) {
      return true;
    }
  }
  return false;
}

std::string gsettings_read(const std::vector<std::string>& args) {
  const CommandResult result = run_command(args);
  if (!result.ok || result.exit_status != 0) {
    return "";
  }
  std::string value = result.stdout_text;
  value.erase(value.find_last_not_of(" \n\r\t") + 1);
  return trim_quotes(value);
}

bool apply_gnome_proxy(const DesktopPlatformChannel* self) {
  const bool mode_ok = command_succeeds({
      "gsettings", "set", "org.gnome.system.proxy", "mode", "manual"});
  const bool http_host = command_succeeds({
      "gsettings", "set", "org.gnome.system.proxy.http", "host",
      self->proxy_host});
  const bool http_port = command_succeeds({
      "gsettings", "set", "org.gnome.system.proxy.http", "port",
      std::to_string(self->proxy_port)});
  const bool https_host = command_succeeds({
      "gsettings", "set", "org.gnome.system.proxy.https", "host",
      self->proxy_host});
  const bool https_port = command_succeeds({
      "gsettings", "set", "org.gnome.system.proxy.https", "port",
      std::to_string(self->proxy_port)});
  const bool socks_host = command_succeeds({
      "gsettings", "set", "org.gnome.system.proxy.socks", "host",
      self->proxy_host});
  const bool socks_port = command_succeeds({
      "gsettings", "set", "org.gnome.system.proxy.socks", "port",
      std::to_string(self->proxy_port)});
  return mode_ok && http_host && http_port && https_host && https_port &&
         socks_host && socks_port;
}

bool disable_gnome_proxy() {
  return command_succeeds(
      {"gsettings", "set", "org.gnome.system.proxy", "mode", "none"});
}

bool apply_kde_proxy(const DesktopPlatformChannel* self) {
  const bool type_ok = command_succeeds({
      "kwriteconfig5", "--file", "kioslaverc", "--group",
      "Proxy Settings", "--key", "ProxyType", "1"});
  const std::string proxy_value =
      "http://" + self->proxy_host + " " + std::to_string(self->proxy_port);
  const bool http_ok = command_succeeds({
      "kwriteconfig5", "--file", "kioslaverc", "--group",
      "Proxy Settings", "--key", "httpProxy", proxy_value});
  const bool https_ok = command_succeeds({
      "kwriteconfig5", "--file", "kioslaverc", "--group",
      "Proxy Settings", "--key", "httpsProxy", proxy_value});
  const bool socks_ok = command_succeeds({
      "kwriteconfig5", "--file", "kioslaverc", "--group",
      "Proxy Settings", "--key", "socksProxy", proxy_value});
  command_succeeds({"qdbus", "org.kde.KIO", "/KIO/Scheduler",
                    "org.kde.KIO.Scheduler.reparseConfiguration", ""});
  return type_ok && http_ok && https_ok && socks_ok;
}

bool disable_kde_proxy() {
  const bool ok = command_succeeds({
      "kwriteconfig5", "--file", "kioslaverc", "--group", "Proxy Settings",
      "--key", "ProxyType", "0"});
  command_succeeds({"qdbus", "org.kde.KIO", "/KIO/Scheduler",
                    "org.kde.KIO.Scheduler.reparseConfiguration", ""});
  return ok;
}

bool apply_proxy_mode(DesktopPlatformChannel* self) {
  if (self->desktop_environment == "gnome") {
    return apply_gnome_proxy(self);
  }
  if (self->desktop_environment == "kde") {
    return apply_kde_proxy(self);
  }
  return false;
}

bool disable_system_proxy(DesktopPlatformChannel* self) {
  if (self->desktop_environment == "gnome") {
    return disable_gnome_proxy();
  }
  if (self->desktop_environment == "kde") {
    return disable_kde_proxy();
  }
  return false;
}

std::string gnome_proxy_mode() {
  return gsettings_read(
      {"gsettings", "get", "org.gnome.system.proxy", "mode"});
}

std::string gnome_proxy_host(const std::string& group) {
  const std::string schema = "org.gnome.system.proxy." + group;
  return gsettings_read({"gsettings", "get", schema, "host"});
}

int gnome_proxy_port(const std::string& group) {
  const std::string schema = "org.gnome.system.proxy." + group;
  const std::string value =
      gsettings_read({"gsettings", "get", schema, "port"});
  return value.empty() ? 0 : std::atoi(value.c_str());
}

std::string kde_proxy_value(const char* key) {
  const CommandResult result = run_command({"kreadconfig5", "--file", "kioslaverc",
                                            "--group", "Proxy Settings",
                                            "--key", key});
  if (!result.ok || result.exit_status != 0) {
    return "";
  }
  std::string value = result.stdout_text;
  value.erase(value.find_last_not_of(" \n\r\t") + 1);
  return value;
}

void refresh_runtime_state(DesktopPlatformChannel* self) {
  self->desktop_environment = detect_desktop_environment();
  self->network_manager_available = network_manager_available();
  self->autostart_enabled = autostart_enabled();
}

std::string state_json(DesktopPlatformChannel* self) {
  refresh_runtime_state(self);

  bool proxy_enabled = false;
  std::string proxy_backend;
  std::string proxy_host = self->proxy_host;
  int proxy_port = self->proxy_port;
  if (self->desktop_environment == "gnome") {
    proxy_backend = "gsettings";
    proxy_enabled = gnome_proxy_mode() == "manual";
    if (proxy_enabled) {
      const std::string detected_host = gnome_proxy_host("http");
      const int detected_port = gnome_proxy_port("http");
      if (!detected_host.empty()) {
        proxy_host = detected_host;
      }
      if (detected_port > 0) {
        proxy_port = detected_port;
      }
    }
  } else if (self->desktop_environment == "kde") {
    proxy_backend = "kioslaverc";
    const std::string detected = kde_proxy_value("httpProxy");
    proxy_enabled = !detected.empty();
    if (proxy_enabled) {
      const std::regex pattern(R"(http://([^ ]+)\s+(\d+))");
      std::smatch match;
      if (std::regex_search(detected, match, pattern) && match.size() >= 3) {
        proxy_host = match[1].str();
        proxy_port = std::stoi(match[2].str());
      }
    }
  }

  const bool tunnel_available =
      self->network_manager_available &&
      tunnel_profile_exists(self->vpn_connection_name);
  const bool tunnel_is_connected =
      tunnel_available && tunnel_connected(self->vpn_connection_name);

  const std::string mode =
      tunnel_is_connected ? "tunnel" : (proxy_enabled ? "proxy" : self->preferred_mode);

  std::ostringstream json;
  json << "{";
  json << "\"isSupported\":true,";
  json << "\"environment\":\"" << json_escape(self->desktop_environment) << "\",";
  json << "\"mode\":\"" << json_escape(mode) << "\",";
  json << "\"trayAvailable\":" << (self->tray_available ? "true" : "false") << ",";
  json << "\"trayEnabled\":" << (self->tray_enabled ? "true" : "false") << ",";
  json << "\"autostartEnabled\":" << (self->autostart_enabled ? "true" : "false") << ",";
  json << "\"networkManagerAvailable\":"
       << (self->network_manager_available ? "true" : "false") << ",";
  json << "\"systemProxy\":{";
  json << "\"enabled\":" << (proxy_enabled ? "true" : "false") << ",";
  json << "\"host\":\"" << json_escape(proxy_host) << "\",";
  json << "\"port\":" << proxy_port << ",";
  json << "\"backend\":\"" << json_escape(proxy_backend) << "\",";
  json << "\"lastAppliedMode\":\"" << json_escape(self->preferred_mode) << "\"";
  json << "},";
  json << "\"tunnel\":{";
  json << "\"available\":" << (tunnel_available ? "true" : "false") << ",";
  json << "\"connected\":" << (tunnel_is_connected ? "true" : "false") << ",";
  json << "\"connectionName\":\"" << json_escape(self->vpn_connection_name) << "\",";
  json << "\"backend\":\"nmcli\",";
  json << "\"lastError\":\"" << json_escape(self->status_message) << "\"";
  json << "},";
  json << "\"statusMessage\":\"" << json_escape(self->status_message) << "\"";
  json << "}";
  return json.str();
}

void update_status_icon(DesktopPlatformChannel* self) {
  if (self->status_icon == nullptr) {
    return;
  }
  gtk_status_icon_set_visible(self->status_icon, self->tray_enabled);
  gtk_status_icon_set_from_icon_name(self->status_icon, "network-vpn-symbolic");
  const std::string json = state_json(self);
  const std::string tooltip =
      "XWorkmate • " + self->desktop_environment + " • " + self->preferred_mode;
  gtk_status_icon_set_tooltip_text(self->status_icon, tooltip.c_str());
}

void show_window(DesktopPlatformChannel* self) {
  gtk_widget_show_all(GTK_WIDGET(self->window));
  gtk_window_present(self->window);
}

void on_open_activate(GtkMenuItem*, gpointer user_data) {
  show_window(static_cast<DesktopPlatformChannel*>(user_data));
}

void on_status_icon_activate(GtkStatusIcon*, gpointer user_data) {
  show_window(static_cast<DesktopPlatformChannel*>(user_data));
}

void on_quit_activate(GtkMenuItem*, gpointer user_data) {
  auto* self = static_cast<DesktopPlatformChannel*>(user_data);
  g_application_quit(G_APPLICATION(self->application));
}

void on_use_proxy_activate(GtkMenuItem*, gpointer user_data) {
  auto* self = static_cast<DesktopPlatformChannel*>(user_data);
  self->preferred_mode = "proxy";
  if (!apply_proxy_mode(self)) {
    self->status_message =
        "Failed to apply system proxy; verify gsettings/kwriteconfig5";
  } else {
    self->status_message = "System proxy enabled";
  }
  update_status_icon(self);
}

void on_use_tunnel_activate(GtkMenuItem*, gpointer user_data) {
  auto* self = static_cast<DesktopPlatformChannel*>(user_data);
  self->preferred_mode = "tunnel";
  if (!disable_system_proxy(self)) {
    self->status_message = "Tunnel mode selected; proxy disable may require manual follow-up";
  } else {
    self->status_message = "Tunnel mode selected";
  }
  update_status_icon(self);
}

void on_connect_tunnel_activate(GtkMenuItem*, gpointer user_data) {
  auto* self = static_cast<DesktopPlatformChannel*>(user_data);
  self->preferred_mode = "tunnel";
  disable_system_proxy(self);
  if (!command_succeeds({"nmcli", "connection", "up", "id",
                         self->vpn_connection_name})) {
    self->status_message = "Failed to connect NetworkManager tunnel";
  } else {
    self->status_message = "Tunnel connected";
  }
  update_status_icon(self);
}

void on_disconnect_tunnel_activate(GtkMenuItem*, gpointer user_data) {
  auto* self = static_cast<DesktopPlatformChannel*>(user_data);
  if (!command_succeeds({"nmcli", "connection", "down", "id",
                         self->vpn_connection_name})) {
    self->status_message = "Failed to disconnect tunnel";
  } else {
    self->status_message = "Tunnel disconnected";
  }
  update_status_icon(self);
}

void on_status_icon_popup(GtkStatusIcon* status_icon,
                          guint button,
                          guint activate_time,
                          gpointer user_data) {
  auto* self = static_cast<DesktopPlatformChannel*>(user_data);
  gtk_menu_popup(GTK_MENU(self->menu), nullptr, nullptr,
                 gtk_status_icon_position_menu, status_icon, button,
                 activate_time);
}

GtkWidget* build_menu(DesktopPlatformChannel* self) {
  GtkWidget* menu = gtk_menu_new();

  GtkWidget* open_item = gtk_menu_item_new_with_label("Open XWorkmate");
  GtkWidget* connect_item = gtk_menu_item_new_with_label("Connect Tunnel");
  GtkWidget* disconnect_item = gtk_menu_item_new_with_label("Disconnect Tunnel");
  GtkWidget* proxy_item = gtk_menu_item_new_with_label("Use Proxy Mode");
  GtkWidget* tunnel_item = gtk_menu_item_new_with_label("Use Tunnel Mode");
  GtkWidget* quit_item = gtk_menu_item_new_with_label("Quit");

  g_signal_connect(open_item, "activate", G_CALLBACK(on_open_activate), self);
  g_signal_connect(connect_item, "activate",
                   G_CALLBACK(on_connect_tunnel_activate), self);
  g_signal_connect(disconnect_item, "activate",
                   G_CALLBACK(on_disconnect_tunnel_activate), self);
  g_signal_connect(proxy_item, "activate", G_CALLBACK(on_use_proxy_activate),
                   self);
  g_signal_connect(tunnel_item, "activate", G_CALLBACK(on_use_tunnel_activate),
                   self);
  g_signal_connect(quit_item, "activate", G_CALLBACK(on_quit_activate), self);

  gtk_menu_shell_append(GTK_MENU_SHELL(menu), open_item);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), connect_item);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), disconnect_item);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), proxy_item);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), tunnel_item);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), quit_item);
  gtk_widget_show_all(menu);
  return menu;
}

void ensure_status_icon(DesktopPlatformChannel* self) {
  if (self->status_icon == nullptr) {
    self->status_icon = gtk_status_icon_new();
    self->menu = build_menu(self);
    g_signal_connect(self->status_icon, "popup-menu",
                     G_CALLBACK(on_status_icon_popup), self);
    g_signal_connect(self->status_icon, "activate",
                     G_CALLBACK(on_status_icon_activate),
                     self);
  }
  update_status_icon(self);
}

FlMethodResponse* success_response_with_json(const std::string& payload) {
  g_autoptr(FlValue) result = fl_value_new_string(payload.c_str());
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

FlMethodResponse* method_error(const char* code, const std::string& message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message.c_str(), nullptr));
}

FlMethodResponse* handle_method_call(DesktopPlatformChannel* self,
                                     FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "getState") == 0) {
    return success_response_with_json(state_json(self));
  }

  if (strcmp(method, "configure") == 0) {
    const char* payload = args == nullptr ? nullptr : fl_value_get_string(args);
    const std::string json = payload == nullptr ? "" : payload;
    if (const auto value = json_string(json, "preferredMode"); value.has_value()) {
      self->preferred_mode = *value;
    }
    if (const auto value = json_string(json, "vpnConnectionName"); value.has_value()) {
      self->vpn_connection_name = *value;
    }
    if (const auto value = json_string(json, "proxyHost"); value.has_value()) {
      self->proxy_host = *value;
    }
    if (const auto value = json_int(json, "proxyPort"); value.has_value()) {
      self->proxy_port = *value;
    }
    if (const auto value = json_bool(json, "trayEnabled"); value.has_value()) {
      self->tray_enabled = *value;
    }
    ensure_status_icon(self);
    return success_response_with_json(state_json(self));
  }

  if (strcmp(method, "setMode") == 0) {
    const char* value = args == nullptr ? nullptr : fl_value_get_string(args);
    if (value == nullptr) {
      return method_error("INVALID_ARGS", "mode is required");
    }
    self->preferred_mode = value;
    if (self->preferred_mode == "proxy") {
      if (!apply_proxy_mode(self)) {
        self->status_message = "Failed to apply system proxy";
      } else {
        self->status_message = "System proxy enabled";
      }
    } else {
      disable_system_proxy(self);
      self->status_message = "Tunnel mode selected";
    }
    update_status_icon(self);
    return success_response_with_json(state_json(self));
  }

  if (strcmp(method, "connectTunnel") == 0) {
    self->preferred_mode = "tunnel";
    disable_system_proxy(self);
    if (!command_succeeds({"nmcli", "connection", "up", "id",
                           self->vpn_connection_name})) {
      return method_error("NM_CONNECT_FAILED",
                          "Failed to connect NetworkManager tunnel");
    }
    self->status_message = "Tunnel connected";
    update_status_icon(self);
    return success_response_with_json(state_json(self));
  }

  if (strcmp(method, "disconnectTunnel") == 0) {
    if (!command_succeeds({"nmcli", "connection", "down", "id",
                           self->vpn_connection_name})) {
      return method_error("NM_DISCONNECT_FAILED", "Failed to disconnect tunnel");
    }
    self->status_message = "Tunnel disconnected";
    update_status_icon(self);
    return success_response_with_json(state_json(self));
  }

  if (strcmp(method, "setAutostart") == 0) {
    const bool enabled = args != nullptr && fl_value_get_bool(args);
    const bool ok = enabled ? write_autostart_file() : remove_autostart_file();
    if (!ok) {
      return method_error("AUTOSTART_FAILED", "Failed to update autostart");
    }
    self->status_message =
        enabled ? "Autostart enabled" : "Autostart disabled";
    update_status_icon(self);
    return success_response_with_json(state_json(self));
  }

  if (strcmp(method, "showWindow") == 0) {
    show_window(self);
    return success_response_with_json(state_json(self));
  }

  return FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
}

void method_call_cb(FlMethodChannel* channel,
                    FlMethodCall* method_call,
                    gpointer user_data) {
  auto* self = static_cast<DesktopPlatformChannel*>(user_data);
  g_autoptr(FlMethodResponse) response = handle_method_call(self, method_call);
  GError* error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error) && error != nullptr) {
    g_warning("Failed to send response: %s", error->message);
    g_error_free(error);
  }
}

}  // namespace

DesktopPlatformChannel* desktop_platform_channel_new(MyApplication* application,
                                                     GtkWindow* window,
                                                     FlView* view) {
  auto* self = new DesktopPlatformChannel();
  self->application = application;
  self->window = window;
  self->view = view;
  self->desktop_environment = detect_desktop_environment();
  ensure_status_icon(self);

  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel =
      fl_method_channel_new(messenger, kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb, self,
                                            nullptr);
  return self;
}

void desktop_platform_channel_free(DesktopPlatformChannel* channel) {
  if (channel == nullptr) {
    return;
  }
  if (channel->status_icon != nullptr) {
    gtk_status_icon_set_visible(channel->status_icon, FALSE);
    g_object_unref(channel->status_icon);
  }
  if (channel->menu != nullptr) {
    gtk_widget_destroy(channel->menu);
  }
  if (channel->channel != nullptr) {
    g_object_unref(channel->channel);
  }
  delete channel;
}
