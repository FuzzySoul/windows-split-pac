use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
};

use eframe::egui::{self, Color32, RichText, Stroke};
use windows_split_pac_gui::{
    DEFAULT_PAC_URL, Language, SplitTestResult, UiSettings, is_valid_proxy_address,
};

const ACCENT: Color32 = Color32::from_rgb(34, 211, 238);
const SUCCESS: Color32 = Color32::from_rgb(74, 222, 128);
const DANGER: Color32 = Color32::from_rgb(251, 113, 133);
const PANEL: Color32 = Color32::from_rgb(20, 31, 53);
const CANVAS: Color32 = Color32::from_rgb(9, 15, 30);

fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([1040.0, 760.0])
            .with_min_inner_size([850.0, 620.0])
            .with_title("Windows Split PAC"),
        ..Default::default()
    };
    eframe::run_native(
        "Windows Split PAC",
        options,
        Box::new(|creation_context| Ok(Box::new(SplitPacApp::new(creation_context)))),
    )
}

struct SplitPacApp {
    root: PathBuf,
    settings: UiSettings,
    custom_rules: String,
    status: String,
    status_is_error: bool,
    service_online: bool,
    pac_enabled: bool,
    backup_available: bool,
    last_test: Option<SplitTestResult>,
}

impl SplitPacApp {
    fn new(creation_context: &eframe::CreationContext<'_>) -> Self {
        configure_visuals(&creation_context.egui_ctx);
        let root = find_project_root();
        let settings = load_settings(&root);
        let custom_rules =
            fs::read_to_string(root.join("rules/user-rules.txt")).unwrap_or_default();
        let mut app = Self {
            root,
            settings,
            custom_rules,
            status: String::new(),
            status_is_error: false,
            service_online: false,
            pac_enabled: false,
            backup_available: false,
            last_test: None,
        };
        app.refresh_status();
        app
    }

    fn text<'a>(&self, chinese: &'a str, english: &'a str) -> &'a str {
        if self.settings.language == Language::Chinese {
            chinese
        } else {
            english
        }
    }

    fn save_local_state(&self) {
        let data_dir = self.root.join("data");
        if fs::create_dir_all(&data_dir).is_ok()
            && let Ok(serialized) = serde_json::to_string_pretty(&self.settings)
        {
            let _ = fs::write(data_dir.join("ui-settings.json"), serialized);
        }
    }

    fn save_rules(&self) -> Result<(), String> {
        fs::write(self.root.join("rules/user-rules.txt"), &self.custom_rules)
            .map_err(|error| format!("Could not save rules: {error}"))
    }

    fn run_script(&self, name: &str, arguments: &[&str]) -> Result<String, String> {
        let output = Command::new("powershell.exe")
            .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"])
            .arg(self.root.join("scripts").join(name))
            .args(arguments)
            .output()
            .map_err(|error| format!("Could not start {name}: {error}"))?;
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_owned();
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        if output.status.success() {
            Ok(stdout)
        } else if stderr.is_empty() {
            Err(stdout)
        } else {
            Err(stderr)
        }
    }

    fn enable_split_routing(&mut self) {
        let proxy = self.settings.proxy_address.trim().to_owned();
        if !is_valid_proxy_address(&proxy) {
            self.fail(self.text(
                "请输入有效的 HTTP 代理地址，例如 192.168.1.100:8080。",
                "Enter a valid HTTP proxy address, for example 192.168.1.100:8080.",
            ));
            return;
        }
        let setup_result = self
            .save_rules()
            .and_then(|_| self.run_script("Install-Dependencies.ps1", &[]))
            .and_then(|_| self.run_script("Build-Pac.ps1", &["-ProxyAddress", &proxy]))
            .and_then(|_| self.run_script("Start-PacServer.ps1", &[]))
            .and_then(|_| self.run_script("Enable-WindowsPac.ps1", &["-PacUrl", DEFAULT_PAC_URL]));

        if let Err(error) = setup_result {
            let _ = self.run_script("Stop-PacServer.ps1", &[]);
            self.fail(&error);
            return;
        }
        let autostart = if self.settings.start_at_logon {
            "Install-Autostart.ps1"
        } else {
            "Uninstall-Autostart.ps1"
        };
        if let Err(error) = self.run_script(autostart, &[]) {
            let _ = self.run_script("Disable-WindowsPac.ps1", &[]);
            let _ = self.run_script("Stop-PacServer.ps1", &[]);
            self.fail(&error);
            return;
        }
        self.save_local_state();
        self.succeed(self.text(
            "智能分流已启用：原有 Windows 代理设置已备份，可在关闭时恢复。",
            "Smart split routing is on: your previous Windows proxy settings are backed up for restore.",
        ));
        self.refresh_status();
    }

    fn disable_split_routing(&mut self) {
        match self
            .run_script("Disable-WindowsPac.ps1", &[])
            .and_then(|_| self.run_script("Stop-PacServer.ps1", &[]))
        {
            Ok(_) => {
                self.succeed(self.text(
                    "Windows PAC 和本机服务已关闭；原有代理设置已恢复（如存在备份）。",
                    "Windows PAC and the local service are off; previous proxy settings were restored when available.",
                ));
                self.refresh_status();
            }
            Err(error) => self.fail(&error),
        }
    }

    fn run_split_test(&mut self) {
        match self.run_script("Test-SplitRouting.ps1", &[]) {
            Ok(json) => match serde_json::from_str::<SplitTestResult>(&json) {
                Ok(result) => {
                    let passed = result.split_routing_verified;
                    self.last_test = Some(result);
                    if passed {
                        self.succeed(
                            self.text("分流规则验证通过。", "Split-routing rules verified."),
                        );
                    } else {
                        self.fail(self.text(
                            "分流规则未通过验证。",
                            "Split-routing rules did not verify.",
                        ));
                    }
                }
                Err(error) => self.fail(&format!("Could not parse split test result: {error}")),
            },
            Err(error) => self.fail(&error),
        }
    }

    fn refresh_status(&mut self) {
        self.service_online = self
            .run_script("Test-SplitRouting.ps1", &[])
            .ok()
            .and_then(|json| serde_json::from_str::<SplitTestResult>(&json).ok())
            .is_some_and(|result| result.pac_server_healthy);
        let windows_status = self
            .run_script("Get-WindowsPacStatus.ps1", &[])
            .ok()
            .and_then(|json| serde_json::from_str::<serde_json::Value>(&json).ok());
        self.pac_enabled = windows_status
            .as_ref()
            .and_then(|value| value.get("enabled").and_then(serde_json::Value::as_bool))
            .unwrap_or(false);
        self.backup_available = windows_status
            .as_ref()
            .and_then(|value| value.get("backup_available").and_then(serde_json::Value::as_bool))
            .unwrap_or(false);
    }

    fn succeed(&mut self, message: &str) {
        self.status = message.to_owned();
        self.status_is_error = false;
    }
    fn fail(&mut self, message: &str) {
        self.status = message.to_owned();
        self.status_is_error = true;
    }
}

impl eframe::App for SplitPacApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        egui::CentralPanel::default().frame(egui::Frame::default().fill(CANVAS)).show(ctx, |ui| {
            ui.add_space(14.0);
            ui.horizontal(|ui| {
                ui.vertical(|ui| {
                    ui.label(RichText::new("WINDOWS SPLIT PAC").size(25.0).strong().color(Color32::WHITE));
                    ui.label(RichText::new(self.text("一键启用 GFWList 智能分流", "One-click GFWList smart routing")).color(ACCENT));
                });
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    egui::ComboBox::from_id_salt("language").selected_text(if self.settings.language == Language::Chinese { "简体中文" } else { "English" }).show_ui(ui, |ui| {
                        ui.selectable_value(&mut self.settings.language, Language::Chinese, "简体中文");
                        ui.selectable_value(&mut self.settings.language, Language::English, "English");
                    });
                });
            });
            ui.add_space(18.0);

            egui::Frame::default().fill(PANEL).stroke(Stroke::new(1.0_f32, Color32::from_rgb(37, 56, 88))).inner_margin(18.0).show(ui, |ui| {
                ui.label(RichText::new(self.text("连接你的 HTTP 代理", "Connect your HTTP proxy")).size(17.0).strong().color(Color32::WHITE));
                ui.label(RichText::new(self.text("只填地址和端口，例如 192.168.1.100:8080。", "Enter only host and port, for example 192.168.1.100:8080.")).color(Color32::from_rgb(148, 163, 184)));
                ui.label(RichText::new(self.text("启用前会备份现有 Windows 代理设置；关闭时自动恢复。", "Your current Windows proxy settings are backed up before enabling and restored when disabled.")).color(Color32::from_rgb(148, 163, 184)));
                ui.add_space(8.0);
                ui.add_sized([460.0, 32.0], egui::TextEdit::singleline(&mut self.settings.proxy_address).hint_text("192.168.1.100:8080"));
                ui.add_space(10.0);
                let autostart_label = self.text("登录后自动启动本机 PAC 服务", "Start the local PAC service after sign-in").to_owned();
                ui.checkbox(&mut self.settings.start_at_logon, autostart_label);
                ui.add_space(12.0);
                ui.horizontal(|ui| {
                    if ui.add_sized([250.0, 42.0], egui::Button::new(RichText::new(self.text("启用智能分流", "Enable smart routing")).strong()).fill(ACCENT)).clicked() { self.enable_split_routing(); }
                    if ui.add_sized([220.0, 42.0], egui::Button::new(self.text("停止并关闭分流", "Stop and disable routing")).fill(Color32::from_rgb(71, 85, 105))).clicked() { self.disable_split_routing(); }
                    if ui.button(self.text("刷新状态", "Refresh")).clicked() { self.refresh_status(); }
                });
            });

            ui.add_space(12.0);
            ui.columns(4, |columns| {
                status_card(&mut columns[0], self.text("PAC 服务", "PAC service"), self.service_online, self.text("本机 8765 端口", "Local port 8765"));
                status_card(&mut columns[1], self.text("Windows 设置", "Windows setting"), self.pac_enabled, self.text("自动代理脚本", "Automatic proxy script"));
                status_card(&mut columns[2], self.text("恢复保障", "Restore safety"), self.backup_available, self.text("原有设置已备份", "Previous settings backed up"));
                status_card(&mut columns[3], self.text("开机自启", "Autostart"), self.settings.start_at_logon, self.text("登录后保持服务", "Keep service after sign-in"));
            });
            ui.add_space(12.0);

            egui::Frame::default().fill(PANEL).stroke(Stroke::new(1.0_f32, Color32::from_rgb(37, 56, 88))).inner_margin(18.0).show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.vertical(|ui| {
                        ui.label(RichText::new(self.text("分流测试", "Split-routing test")).size(17.0).strong().color(Color32::WHITE));
                        ui.label(RichText::new(self.text("验证一个代理命中域名和一个直连域名的 PAC 决策。", "Verify PAC decisions for one proxied domain and one direct domain.")).color(Color32::from_rgb(148, 163, 184)));
                    });
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        if ui.add_sized([145.0, 36.0], egui::Button::new(self.text("测试是否分流", "Run split test")).fill(Color32::from_rgb(79, 70, 229))).clicked() { self.run_split_test(); }
                    });
                });
                if let Some(result) = &self.last_test {
                    let color = if result.split_routing_verified { SUCCESS } else { DANGER };
                    ui.add_space(8.0);
                    ui.label(RichText::new(format!("{}: {} | {}: {}", result.proxy_domain, result.proxy_decision, result.direct_domain, result.direct_decision)).color(color));
                }
            });
            ui.add_space(12.0);

            egui::CollapsingHeader::new(self.text("自定义规则与诊断", "Custom rules and diagnostics")).show(ui, |ui| {
                ui.label(self.text("一行一条规则。||example.com 强制代理，@@||example.com 强制直连。保存后再次点击“启用智能分流”即可生效。", "One rule per line. ||example.com forces proxy; @@||example.com forces direct. Save, then enable smart routing to apply."));
                ui.add(egui::TextEdit::multiline(&mut self.custom_rules).desired_rows(5).code_editor());
                if ui.button(self.text("保存规则", "Save rules")).clicked() {
                    match self.save_rules() { Ok(_) => self.succeed(self.text("规则已保存。", "Rules saved.")), Err(error) => self.fail(&error) }
                }
            });
            ui.add_space(10.0);
            ui.label(RichText::new(&self.status).color(if self.status_is_error { DANGER } else { SUCCESS }));
            ui.label(RichText::new(self.text("启用后，Windows 会使用 http://127.0.0.1:8765/proxy.pac。", "When enabled, Windows uses http://127.0.0.1:8765/proxy.pac.")).small().color(Color32::from_rgb(100, 116, 139)));
        });
    }
}

fn configure_visuals(ctx: &egui::Context) {
    let mut visuals = egui::Visuals::dark();
    visuals.panel_fill = CANVAS;
    visuals.window_fill = PANEL;
    visuals.override_text_color = Some(Color32::from_rgb(226, 232, 240));
    ctx.set_visuals(visuals);
}

fn status_card(ui: &mut egui::Ui, title: &str, active: bool, detail: &str) {
    let color = if active {
        SUCCESS
    } else {
        Color32::from_rgb(148, 163, 184)
    };
    egui::Frame::default()
        .fill(PANEL)
        .stroke(Stroke::new(1.0_f32, Color32::from_rgb(37, 56, 88)))
        .inner_margin(14.0)
        .show(ui, |ui| {
            ui.label(RichText::new(title).strong().color(Color32::WHITE));
            ui.label(
                RichText::new(if active { "ACTIVE" } else { "OFFLINE" })
                    .color(color)
                    .strong(),
            );
            ui.label(
                RichText::new(detail)
                    .small()
                    .color(Color32::from_rgb(148, 163, 184)),
            );
        });
}

fn find_project_root() -> PathBuf {
    let executable = std::env::current_exe().unwrap_or_default();
    for directory in executable.ancestors() {
        if directory.join("scripts").is_dir() && directory.join("rules").is_dir() {
            return directory.to_path_buf();
        }
    }
    std::env::current_dir().unwrap_or_else(|_| Path::new(".").to_path_buf())
}

fn load_settings(root: &Path) -> UiSettings {
    fs::read_to_string(root.join("data/ui-settings.json"))
        .ok()
        .and_then(|content| serde_json::from_str(&content).ok())
        .unwrap_or_default()
}
