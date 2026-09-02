#![windows_subsystem = "windows"]
use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
    sync::{Arc, mpsc},
    thread,
};

use eframe::egui::{self, Color32, RichText, Stroke};
use windows_split_pac_gui::{
    ApplyReport, CheckStatus, Diagnostics, Language, PacEngine, ServiceIdentity, SimpleRules,
    SplitRoutingEngine, SplitTestResult, UiSettings, is_valid_proxy_address,
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

/// Background operation result delivered to the UI thread.
enum WorkerOutcome {
    Test {
        domain: String,
        result: Result<String, String>,
    },
    Apply {
        result: Result<ApplyReport, String>,
    },
    Restart {
        result: Result<(), String>,
    },
    RestartEdge {
        result: Result<String, String>,
    },
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
    service_identity: Option<ServiceIdentity>,
    simple_proxy_text: String,
    simple_direct_text: String,
    autostart_online: bool,
    raw_rules_mode: bool,
    rules_window_open: bool,
    new_rule_domain: String,
    new_rule_proxy: bool,
    rule_test_result: String,
    show_proxy_config: bool,
    worker_rx: mpsc::Receiver<WorkerOutcome>,
    busy: bool,
    busy_label: String,
    success_popup: Option<String>,
    autostart_action: Option<String>,
}

impl SplitPacApp {
    fn new(creation_context: &eframe::CreationContext<'_>) -> Self {
        configure_visuals(&creation_context.egui_ctx);
        let root = find_project_root();
        let settings = load_settings(&root);
        let custom_rules = fs::read_to_string(Path::new("C:\\proxy\\user-rules.txt"))
            .or_else(|_| fs::read_to_string(root.join("rules/user-rules.txt")))
            .unwrap_or_default();
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
            service_identity: None,
            simple_proxy_text: String::new(),
            simple_direct_text: String::new(),
            autostart_online: false,
            raw_rules_mode: false,
            rules_window_open: false,
            new_rule_domain: String::new(),
            new_rule_proxy: true,
            rule_test_result: String::new(),
            show_proxy_config: true,
            worker_rx: mpsc::channel().1,
            busy: false,
            busy_label: String::new(),
            success_popup: None,
            autostart_action: None,
        };
        app.sync_bucket_texts();
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
        let live = Path::new("C:\\proxy\\user-rules.txt");
        // Prefer the live C:\proxy file as the single source of truth. On a
        // fresh machine, try to create C:\proxy; if that fails (e.g. no admin
        // right to write at drive root), fall back to the repo rules file.
        let use_live = if Path::new("C:\\proxy").exists() {
            true
        } else {
            fs::create_dir_all("C:\\proxy").is_ok()
        };
        let target = if use_live {
            live.to_path_buf()
        } else {
            self.root.join("rules/user-rules.txt")
        };
        fs::write(&target, &self.custom_rules)
            .map_err(|error| format!("Could not save rules to {}: {error}", target.display()))
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
        if self.busy {
            return;
        }
        let proxy = self.settings.proxy_address.trim().to_owned();
        if !is_valid_proxy_address(&proxy) {
            self.fail(self.text(
                "请输入有效的 HTTP 代理地址，例如 192.168.1.100:8080。",
                "Enter a valid HTTP proxy address, for example 192.168.1.100:8080.",
            ));
            return;
        }
        if let Err(error) = self.save_rules() {
            self.fail(&error);
            return;
        }
        // Defer autostart changes until apply succeeds (the PAC must exist
        // first; Install-Autostart no longer requires dist\proxy.pac but the
        // task is only meaningful after a successful apply).
        let autostart = if self.settings.start_at_logon {
            "Install-Autostart.ps1"
        } else {
            "Uninstall-Autostart.ps1"
        };
        self.autostart_action = Some(autostart.to_string());
        self.save_local_state();
        self.spawn_apply(proxy);
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

    /// Rebuild the two bucket text areas from the current rules file text.
    fn sync_bucket_texts(&mut self) {
        let rules = SimpleRules::parse(&self.custom_rules);
        self.simple_proxy_text = rules.proxy.join("\n");
        self.simple_direct_text = rules.direct.join("\n");
    }

    /// The model currently shown in the three-bucket editor.
    fn simple_rules_from_text(&self) -> SimpleRules {
        SimpleRules::from_bucket_text(&self.simple_proxy_text, &self.simple_direct_text)
    }

    /// "Save & apply": render buckets/raw text to file, then apply in background.
    fn apply_simple_rules(&mut self) {
        if self.busy {
            return;
        }
        if !self.raw_rules_mode {
            let rendered = self.simple_rules_from_text().render();
            self.custom_rules = rendered;
        }
        if let Err(error) = self.save_rules() {
            self.fail(&error);
            return;
        }
        let proxy = self.settings.proxy_address.trim().to_owned();
        let proxy = if is_valid_proxy_address(&proxy) {
            proxy
        } else {
            String::new()
        };
        self.spawn_apply(proxy);
    }

    /// The current rules as (domain, is_proxy) pairs for the manager window.
    fn rules_list(&self) -> Vec<(String, bool)> {
        let rules = SimpleRules::parse(&self.custom_rules);
        let mut out: Vec<(String, bool)> = Vec::new();
        for d in &rules.proxy {
            out.push((d.clone(), true));
        }
        for d in &rules.direct {
            out.push((d.clone(), false));
        }
        out
    }

    /// Test one domain against the real PAC file (background, non-blocking).
    fn test_rule(&mut self, domain: String) {
        self.spawn_test_rule(domain);
    }

    /// Add a rule from the popup input. Tolerates arbitrary pasted text:
    /// a full URL, www-prefixed domain, IP:port -> extract_domain() normalises it.
    fn add_rule_from_input(&mut self) {
        let raw = self.new_rule_domain.trim().to_string();
        let Some(domain) = SimpleRules::extract_domain(&raw) else {
            self.rule_test_result = format!(
                "{}: {raw}",
                self.text(
                    "无法识别域名，请粘贴完整网址或域名",
                    "Could not extract a domain from"
                )
            );
            return;
        };
        if self.new_rule_proxy {
            self.simple_proxy_text.push_str(&format!("\n{domain}"));
        } else {
            self.simple_direct_text.push_str(&format!("\n{domain}"));
        }
        self.custom_rules = self.simple_rules_from_text().render();
        self.new_rule_domain.clear();
        self.rule_test_result = format!(
            "{}: {domain}（{}）",
            self.text("已提取并加入", "Extracted and added"),
            self.text("点保存并应用生效", "click Save & apply to make live")
        );
    }

    /// Optional manual restart of the PAC service (background, non-blocking).
    fn restart_service(&mut self) {
        self.spawn_restart();
    }

    /// Start a background apply and show progress. Never blocks the UI thread.
    fn spawn_apply(&mut self, proxy: String) {
        if self.busy {
            return;
        }
        let (tx, rx) = mpsc::channel();
        let root = self.root.clone();
        self.worker_rx = rx;
        self.busy = true;
        self.busy_label = self
            .text(
                "正在应用规则（生成 PAC/刷新代理）…",
                "Applying rules (PAC/refresh)…",
            )
            .to_string();
        self.status = self.busy_label.clone();
        self.status_is_error = false;
        thread::spawn(move || {
            let engine = PacEngine::new(root);
            let result = engine.apply(&proxy);
            let _ = tx.send(WorkerOutcome::Apply { result });
        });
    }

    fn spawn_test_rule(&mut self, domain: String) {
        if self.busy {
            return;
        }
        let (tx, rx) = mpsc::channel();
        let root = self.root.clone();
        self.worker_rx = rx;
        self.busy = true;
        self.busy_label = format!("{} {domain} …", self.text("正在测试", "Testing"));
        self.status = self.busy_label.clone();
        self.status_is_error = false;
        thread::spawn(move || {
            let engine = PacEngine::new(root);
            let result = engine.test_domain(&domain);
            let _ = tx.send(WorkerOutcome::Test { domain, result });
        });
    }

    fn spawn_restart(&mut self) {
        if self.busy {
            return;
        }
        let (tx, rx) = mpsc::channel();
        let root = self.root.clone();
        self.worker_rx = rx;
        self.busy = true;
        self.busy_label = self
            .text("正在重启分流服务…", "Restarting PAC service…")
            .to_string();
        self.status = self.busy_label.clone();
        self.status_is_error = false;
        thread::spawn(move || {
            let engine = PacEngine::new(root);
            let result = engine.restart().map(|_| ());
            let _ = tx.send(WorkerOutcome::Restart { result });
        });
    }

    /// Restart Microsoft Edge in the background so it re-reads the PAC.
    fn spawn_restart_edge(&mut self) {
        if self.busy {
            return;
        }
        let (tx, rx) = mpsc::channel();
        let root = self.root.clone();
        self.worker_rx = rx;
        self.busy = true;
        self.busy_label = self
            .text(
                "正在重启 Edge 以加载新规则…",
                "Restarting Edge to load new rules…",
            )
            .to_string();
        self.status = self.busy_label.clone();
        self.status_is_error = false;
        thread::spawn(move || {
            let engine = PacEngine::new(root);
            let result = engine.restart_edge();
            let _ = tx.send(WorkerOutcome::RestartEdge { result });
        });
    }

    /// Drain background results and update the UI (called every frame).
    fn poll_worker(&mut self) {
        while let Ok(outcome) = self.worker_rx.try_recv() {
            self.busy = false;
            match outcome {
                WorkerOutcome::Test { domain, result } => match result {
                    Ok(decision) => {
                        self.rule_test_result = format!("{domain} → {decision}");
                        self.status = self.rule_test_result.clone();
                        self.status_is_error = false;
                    }
                    Err(error) => {
                        self.rule_test_result = format!("{domain} → {error}");
                        self.status = self.rule_test_result.clone();
                        self.status_is_error = true;
                    }
                },
                WorkerOutcome::Apply { result } => match result {
                    Ok(report) if report.errors.is_empty() && report.pac_ok => {
                        let msg = self
                            .text(
                                "✅ 规则已应用，正在重启 Edge 使其生效…",
                                "✅ Rules applied; restarting Edge to make them effective…",
                            )
                            .to_string();
                        self.succeed(&msg);
                        self.success_popup = Some(msg);
                        if let Some(script) = self.autostart_action.take()
                            && let Err(error) = self.run_script(&script, &[])
                        {
                            self.fail(&format!(
                                "{}: {error}",
                                self.text("自启设置失败", "Autostart setup failed")
                            ));
                        }
                        self.spawn_restart_edge();
                    }
                    Ok(report) => {
                        self.autostart_action = None;
                        self.fail(&format!(
                            "{}: {}",
                            self.text("应用未完成", "Apply incomplete"),
                            report.errors.join("; ")
                        ))
                    }
                    Err(error) => {
                        self.autostart_action = None;
                        self.fail(&format!(
                            "{}: {error}",
                            self.text("应用失败", "Apply failed")
                        ))
                    }
                },
                WorkerOutcome::Restart { result } => match result {
                    Ok(_) => {
                        self.succeed(self.text("分流服务已重启。", "PAC service restarted."));
                        self.refresh_status();
                    }
                    Err(error) => self.fail(&error),
                },
                WorkerOutcome::RestartEdge { result } => match result {
                    Ok(_) => {
                        self.succeed(self.text(
                            "规则已生效，已自动重启 Edge（可用 --restore-last-session 恢复标签页）。",
                            "Rules applied; Edge restarted to load new PAC.",
                        ));
                    }
                    Err(error) => self.fail(&format!(
                        "{}: {error}",
                        self.text("重启 Edge 失败", "Restart Edge failed")
                    )),
                },
            }
        }
    }

    /// Full "connect your HTTP proxy" configuration panel.
    fn proxy_config_panel(&mut self, ui: &mut egui::Ui) {
        egui::Frame::default()
            .fill(PANEL)
            .stroke(Stroke::new(1.0_f32, Color32::from_rgb(37, 56, 88)))
            .inner_margin(18.0)
            .show(ui, |ui| {
                ui.label(
                    RichText::new(self.text("连接你的 HTTP 代理", "Connect your HTTP proxy"))
                        .size(17.0)
                        .strong()
                        .color(Color32::WHITE),
                );
                ui.label(
                    RichText::new(self.text(
                        "只填地址和端口，例如 192.168.1.100:8080。",
                        "Enter only host and port, for example 192.168.1.100:8080.",
                    ))
                    .color(Color32::from_rgb(148, 163, 184)),
                );
                ui.label(
                    RichText::new(self.text(
                        "启用前会备份现有 Windows 代理设置；关闭时自动恢复。",
                        "Your current Windows proxy settings are backed up before enabling and restored when disabled.",
                    ))
                    .color(Color32::from_rgb(148, 163, 184)),
                );
                ui.add_space(8.0);
                ui.add_sized(
                    [460.0, 32.0],
                    egui::TextEdit::singleline(&mut self.settings.proxy_address)
                        .hint_text("192.168.1.100:8080"),
                );
                ui.add_space(10.0);
                let autostart_label = self
                    .text(
                        "登录后自动启动本机 PAC 服务",
                        "Start the local PAC service after sign-in",
                    )
                    .to_owned();
                ui.checkbox(&mut self.settings.start_at_logon, autostart_label);
                ui.add_space(12.0);
                ui.horizontal(|ui| {
                    if self.service_online {
                        let collapse_label = self.text("收起设置", "Collapse settings");
                        if ui.button(collapse_label).clicked() {
                            self.show_proxy_config = false;
                        }
                    }
                    if ui
                        .add_sized(
                            [250.0, 42.0],
                            egui::Button::new(
                                RichText::new(self.text("启用智能分流", "Enable smart routing"))
                                    .strong(),
                            )
                            .fill(ACCENT),
                        )
                        .clicked()
                    {
                        self.enable_split_routing();
                    }
                    if ui
                        .add_sized(
                            [220.0, 42.0],
                            egui::Button::new(
                                self.text("停止并关闭分流", "Stop and disable routing"),
                            )
                            .fill(Color32::from_rgb(71, 85, 105)),
                        )
                        .clicked()
                    {
                        self.disable_split_routing();
                    }
                    if ui.button(self.text("刷新状态", "Refresh")).clicked() {
                        self.refresh_status();
                    }
                });
            });
    }

    fn refresh_status(&mut self) {
        // Authoritative source: who is actually listening/serving/registered.
        self.service_identity = self
            .run_script("Get-ServiceIdentity.ps1", &[])
            .ok()
            .and_then(|json| serde_json::from_str::<ServiceIdentity>(&json).ok());

        let id = self.service_identity.as_ref();
        // Card 1 - PAC service: a real listener responds to /proxy.pac.
        self.service_online = id.is_some_and(|id| id.server_running && id.pac_http_ok);
        // Card 2 - Windows setting: Windows is pointed at our PAC.
        self.pac_enabled = id.is_some_and(|id| id.windows_using_our_pac);
        // Card 3 - restore safety: a Windows proxy backup exists on disk.
        self.backup_available =
            fs::metadata(self.root.join("data/windows-proxy-backup.json")).is_ok();
        // Card 4 - autostart: the real PACServer scheduled task exists.
        self.autostart_online = id.is_some_and(|id| id.autostart_real.exists);
    }

    fn succeed(&mut self, message: &str) {
        self.status = message.to_owned();
        self.status_is_error = false;
    }
    fn fail(&mut self, message: &str) {
        self.status = message.to_owned();
        self.status_is_error = true;
    }

    /// Render a single-line "current service" recognition banner.
    fn service_banner(&self, ui: &mut egui::Ui) {
        let Some(id) = &self.service_identity else {
            ui.label(
                RichText::new(self.text(
                    "无法识别当前服务（请点击“刷新状态”）。",
                    "Could not identify the current service (click Refresh).",
                ))
                .color(Color32::from_rgb(148, 163, 184)),
            );
            return;
        };

        let (color, text) = if id.real_service_active() {
            let mut msg = format!(
                "{}: serve_pac.py  (PID {})  →  {}",
                self.text("当前由真实服务驱动", "Driven by the real service"),
                id.pid
                    .map(|p| p.to_string())
                    .unwrap_or_else(|| "?".to_owned()),
                id.pac_proxy,
            );
            if !id.pid_file_matches {
                msg.push_str(&format!(
                    "  |  {} (pid 文件 {} 已过期)",
                    self.text("警告", "warning"),
                    id.pid_file_value.map(|v| v.to_string()).unwrap_or_default()
                ));
            }
            (SUCCESS, msg)
        } else if id.server_running {
            (
                DANGER,
                format!(
                    "{}: {} (PID {})",
                    self.text("当前由其他服务驱动", "Driven by another service"),
                    id.service_label(),
                    id.pid
                        .map(|p| p.to_string())
                        .unwrap_or_else(|| "?".to_owned()),
                ),
            )
        } else {
            (
                Color32::from_rgb(148, 163, 184),
                self.text(
                    "当前无 PAC 服务在运行",
                    "No PAC service is currently running",
                )
                .to_owned(),
            )
        };
        ui.label(RichText::new(text).color(color));
    }

    /// Build the diagnostics list for the advanced drawer from the last identity.
    fn diagnostics(&self) -> Option<Diagnostics> {
        self.service_identity
            .as_ref()
            .map(Diagnostics::from_identity)
    }

    /// Localized label for a diagnostic check key.
    fn diag_label(&self, key: &str) -> &'static str {
        match key {
            "service" => self.text("服务", "Service"),
            "healthz" => self.text("健康检查", "Health"),
            "pid_file" => self.text("PID 文件", "PID file"),
            "windows_pac" => self.text("Windows 使用本 PAC", "Windows PAC"),
            "autostart" => self.text("自启任务", "Autostart"),
            "rules_sync" => self.text("规则同步", "Rules sync"),
            _ => "?",
        }
    }
}

impl eframe::App for SplitPacApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.poll_worker();
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
            if !self.status.is_empty() {
                ui.label(
                    RichText::new(&self.status)
                        .color(if self.status_is_error { DANGER } else { SUCCESS })
                        .size(14.0),
                );
                ui.add_space(6.0);
            }
            if self.busy {
                ui.horizontal(|ui| {
                    ui.spinner();
                    ui.label(
                        RichText::new(&self.busy_label)
                            .color(Color32::from_rgb(148, 163, 184)),
                    );
                });
                ui.add_space(8.0);
            }

            if !self.service_online || self.show_proxy_config {
                self.proxy_config_panel(ui);
            } else {
                egui::Frame::default()
                    .fill(PANEL)
                    .stroke(Stroke::new(1.0_f32, Color32::from_rgb(37, 56, 88)))
                    .inner_margin(14.0)
                    .show(ui, |ui| {
                        ui.horizontal(|ui| {
                            let detected = self.text(
                                "已检测到分流服务运行中，无需重复配置上游代理。",
                                "PAC service detected; upstream already configured.",
                            );
                            let change_label = self.text("修改代理设置", "Change proxy settings");
                            ui.label(RichText::new(detected).color(SUCCESS));
                            if ui.button(change_label).clicked() {
                                self.show_proxy_config = true;
                            }
                        });
                    });
            }

            ui.add_space(12.0);
            ui.columns(4, |columns| {
                status_card(&mut columns[0], self.text("PAC 服务", "PAC service"), self.service_online, self.text("本机 8765 端口", "Local port 8765"));
                status_card(&mut columns[1], self.text("Windows 设置", "Windows setting"), self.pac_enabled, self.text("自动代理脚本", "Automatic proxy script"));
                status_card(&mut columns[2], self.text("恢复保障", "Restore safety"), self.backup_available, self.text("原有设置已备份", "Previous settings backed up"));
                status_card(&mut columns[3], self.text("开机自启", "Autostart"), self.autostart_online, self.text("PACServer 计划任务", "PACServer scheduled task"));
            });
            ui.add_space(8.0);
            egui::Frame::default().fill(PANEL).stroke(Stroke::new(1.0_f32, Color32::from_rgb(37, 56, 88))).inner_margin(12.0).show(ui, |ui| {
                ui.label(RichText::new(self.text("当前服务识别", "Current service")).size(13.0).strong().color(Color32::from_rgb(148, 163, 184)));
                ui.add_space(4.0);
                self.service_banner(ui);
            });
            egui::CollapsingHeader::new(self.text("诊断（高级）", "Diagnostics (advanced)"))
                .default_open(true)
                .show(ui, |ui| {
                    match self.diagnostics() {
                        None => {
                            ui.label(
                                RichText::new(self.text(
                                    "点击“刷新状态”获取诊断。",
                                    "Click Refresh to load diagnostics.",
                                ))
                                .color(Color32::from_rgb(148, 163, 184)),
                            );
                        }
                        Some(diag) => {
                            for item in &diag.items {
                                let (tag, color) = match item.status {
                                    CheckStatus::Pass => ("✅", SUCCESS),
                                    CheckStatus::Warn => ("⚠️", Color32::from_rgb(251, 191, 36)),
                                    CheckStatus::Fail => ("❌", DANGER),
                                    CheckStatus::Info => ("ℹ️", Color32::from_rgb(148, 163, 184)),
                                };
                                ui.label(
                                    RichText::new(format!(
                                        "{} {}: {}",
                                        tag,
                                        self.diag_label(&item.key),
                                        item.detail
                                    ))
                                    .color(color),
                                );
                            }
                        }
                    }
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

            ui.horizontal(|ui| {
                let open_label = self.text("打开规则管理（弹窗）", "Open rule manager (popup)");
                let restart_label = self.text("重启分流服务", "Restart service");
                if ui
                    .button(RichText::new(open_label).strong())
                    .clicked()
                {
                    self.rules_window_open = true;
                }
                if ui.button(restart_label).clicked() {
                    self.restart_service();
                }
            });
            ui.add_space(10.0);
            ui.label(RichText::new(&self.status).color(if self.status_is_error { DANGER } else { SUCCESS }));
            ui.label(RichText::new(self.text("启用后，Windows 会使用 http://127.0.0.1:8765/proxy.pac。", "When enabled, Windows uses http://127.0.0.1:8765/proxy.pac.")).small().color(Color32::from_rgb(100, 116, 139)));
        });

        // ---- Success popup ----
        if let Some(msg) = self.success_popup.clone() {
            let mut open = true;
            let title = self.text("提示", "Notice");
            let ok_label = self.text("知道了", "OK");
            let mut dismiss = false;
            egui::Window::new(title)
                .open(&mut open)
                .collapsible(false)
                .resizable(false)
                .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
                .show(ctx, |ui| {
                    ui.label(RichText::new(&msg).color(SUCCESS).size(16.0));
                    if ui.button(ok_label).clicked() {
                        dismiss = true;
                    }
                });
            if dismiss || !open {
                self.success_popup = None;
            }
        }

        // ---- Rule manager popup ----
        if self.rules_window_open {
            let mut open = true;
            let window_title = self.text("规则管理", "Rule manager");
            let save_label = self.text("保存并应用（无需重启）", "Save & apply (no restart)");
            let current_label = self.text(
                "当前规则清单（线上 user-rules.txt）",
                "Current rules (live user-rules.txt)",
            );
            let test_label = self.text("测试", "Test");
            let add_title = self.text("添加规则", "Add rule");
            let proxy_label = self.text("走代理", "Proxy");
            let direct_label = self.text("直连", "Direct");
            let add_btn = self.text("添加", "Add");
            egui::Window::new(window_title)
                .open(&mut open)
                .resizable(true)
                .default_size([520.0, 600.0])
                .show(ctx, |ui| {
                    ui.horizontal(|ui| {
                        ui.label(current_label);
                        if ui.button(save_label).clicked() {
                            self.apply_simple_rules();
                        }
                    });
                    if !self.rule_test_result.is_empty() {
                        ui.label(RichText::new(&self.rule_test_result).color(ACCENT));
                    }
                    ui.separator();
                    egui::ScrollArea::vertical()
                        .max_height(320.0)
                        .show(ui, |ui| {
                            for (domain, is_proxy) in self.rules_list() {
                                ui.horizontal(|ui| {
                                    let tag = if is_proxy {
                                        if self.settings.language == Language::Chinese {
                                            "🌐 代理"
                                        } else {
                                            "PROXY"
                                        }
                                    } else if self.settings.language == Language::Chinese {
                                        "🏠 直连"
                                    } else {
                                        "DIRECT"
                                    };
                                    ui.label(RichText::new(tag).color(if is_proxy {
                                        ACCENT
                                    } else {
                                        Color32::from_rgb(148, 163, 184)
                                    }));
                                    ui.monospace(domain.clone());
                                    if ui.button(test_label).clicked() {
                                        self.test_rule(domain.clone());
                                    }
                                });
                            }
                        });
                    ui.separator();
                    ui.horizontal(|ui| {
                        ui.label(add_title);
                        ui.selectable_value(&mut self.new_rule_proxy, true, proxy_label);
                        ui.selectable_value(&mut self.new_rule_proxy, false, direct_label);
                    });
                    ui.horizontal(|ui| {
                        ui.add(
                            egui::TextEdit::singleline(&mut self.new_rule_domain)
                                .hint_text("example.com")
                                .desired_width(220.0),
                        );
                        if ui.button(add_btn).clicked() {
                            self.add_rule_from_input();
                        }
                    });
                });
            if !open {
                self.rules_window_open = false;
            }
        }
    }
}

fn configure_visuals(ctx: &egui::Context) {
    let mut fonts = egui::FontDefinitions::default();
    fonts.font_data.insert(
        "noto-sans-sc".to_owned(),
        Arc::new(egui::FontData::from_static(include_bytes!(
            "../../assets/fonts/NotoSansSC[wght].ttf"
        ))),
    );
    fonts
        .families
        .entry(egui::FontFamily::Proportional)
        .or_default()
        .insert(0, "noto-sans-sc".to_owned());
    fonts
        .families
        .entry(egui::FontFamily::Monospace)
        .or_default()
        .push("noto-sans-sc".to_owned());
    ctx.set_fonts(fonts);

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
