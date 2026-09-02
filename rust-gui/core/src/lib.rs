use serde::{Deserialize, Serialize};
use std::{
    fs,
    path::PathBuf,
    process::{Command, Stdio},
};

pub const DEFAULT_PAC_URL: &str = "http://127.0.0.1:8765/proxy.pac";

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum Language {
    #[default]
    Chinese,
    English,
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct UiSettings {
    pub proxy_address: String,
    pub start_at_logon: bool,
    pub language: Language,
}

#[derive(Debug, Deserialize)]
pub struct SplitTestResult {
    pub pac_server_healthy: bool,
    pub proxy_domain: String,
    pub proxy_decision: String,
    pub direct_domain: String,
    pub direct_decision: String,
    pub split_routing_verified: bool,
}

/// The kind of PAC server detected listening on the local port.
/// The JSON form uses snake_case (e.g. "real_serve_pac") to match the
/// PowerShell detection script output.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ServerKind {
    #[default]
    None,
    RealServePac,
    GuiPacServer,
    Unknown,
}

/// A scheduled task state (existence + run state), as reported by PowerShell.
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct ScheduledTaskState {
    pub exists: bool,
    pub name: String,
    pub state: String,
}

/// Current local PAC service identity, parsed from the JSON emitted by
/// `scripts/Get-ServiceIdentity.ps1`. All fields have `#[serde(default)]` so
/// the GUI degrades gracefully if PowerShell omits a field.
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct ServiceIdentity {
    pub server_running: bool,
    pub server_kind: ServerKind,
    pub pid: Option<u32>,
    pub pid_file_matches: bool,
    pub pid_file_value: Option<u32>,
    pub port: u16,
    pub pac_url: String,
    pub pac_http_ok: bool,
    pub pac_proxy: String,
    pub healthz_ok: bool,
    pub healthz_pid: Option<u32>,
    pub server_cmd: String,
    pub auto_config_url: String,
    pub proxy_enable: bool,
    pub proxy_server: String,
    pub proxy_override: String,
    pub auto_detect: bool,
    pub windows_using_our_pac: bool,
    pub autostart_real: ScheduledTaskState,
    pub autostart_gui: ScheduledTaskState,
    pub rule_file_diff: RuleFileDiff,
}

/// Difference between the online rules file and the repo's default rules file.
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct RuleFileDiff {
    pub online_rules: usize,
    pub gui_rules: usize,
    pub in_sync: bool,
    pub online_file: String,
    pub repo_file: String,
}

impl ServiceIdentity {
    /// A short, human-readable label for who is currently driving the PAC.
    /// Returns plain ASCII so it is safe in any UI/log context.
    pub fn service_label(&self) -> &'static str {
        if self.pid.is_none() {
            "none"
        } else {
            match self.server_kind {
                ServerKind::RealServePac => "real (serve_pac.py)",
                ServerKind::GuiPacServer => "gui (pac_server.py)",
                ServerKind::Unknown => "unknown",
                ServerKind::None => "none",
            }
        }
    }

    /// True when a real serve_pac.py service is running, on our port,
    /// and Windows is actually using our PAC.
    pub fn real_service_active(&self) -> bool {
        self.server_running
            && self.server_kind == ServerKind::RealServePac
            && self.windows_using_our_pac
    }

    /// True when the rules file on disk is out of sync with this repo's default.
    /// Returns false when there is no rule data at all (e.g. an empty/unknown
    /// identity), so an absent snapshot never falsely alarms as "out of sync".
    pub fn rules_out_of_sync(&self) -> bool {
        let has_any_rules = self.rule_file_diff.online_rules + self.rule_file_diff.gui_rules > 0;
        has_any_rules && !self.rule_file_diff.in_sync
    }
}

/// Severity of a diagnostic check surfaced in the GUI's advanced drawer.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CheckStatus {
    #[default]
    Info,
    Pass,
    Warn,
    Fail,
}

/// One named check with a severity and a factual detail line.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DiagnosticItem {
    pub key: String,
    pub status: CheckStatus,
    pub detail: String,
}

/// Aggregate diagnostics derived from a `ServiceIdentity`. The GUI renders the
/// items as a list; `healthy` is false when any check is Warn or Fail.
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Diagnostics {
    pub items: Vec<DiagnosticItem>,
    pub healthy: bool,
}

impl Diagnostics {
    pub fn from_identity(id: &ServiceIdentity) -> Self {
        let mut items: Vec<DiagnosticItem> = Vec::new();
        let mut push = |key: &str, status: CheckStatus, detail: String| {
            items.push(DiagnosticItem {
                key: key.to_string(),
                status,
                detail,
            });
        };

        if id.server_running && id.pac_http_ok {
            push(
                "service",
                CheckStatus::Pass,
                format!(
                    "{} pid={} port={}",
                    id.service_label(),
                    id.pid.map(|p| p.to_string()).unwrap_or_default(),
                    id.port
                ),
            );
        } else {
            push(
                "service",
                CheckStatus::Fail,
                "no PAC server responding".to_string(),
            );
        }

        if id.server_running {
            if id.healthz_ok {
                push(
                    "healthz",
                    CheckStatus::Pass,
                    format!(
                        "ok pid={}",
                        id.healthz_pid.map(|p| p.to_string()).unwrap_or_default()
                    ),
                );
            } else {
                push(
                    "healthz",
                    CheckStatus::Warn,
                    "no /healthz endpoint".to_string(),
                );
            }
        }

        match (id.pid, id.pid_file_matches, id.pid_file_value) {
            (Some(_), true, _) => push(
                "pid_file",
                CheckStatus::Pass,
                "matches live listener".to_string(),
            ),
            (Some(real), false, Some(stale)) => push(
                "pid_file",
                CheckStatus::Warn,
                format!("pid file stale ({stale}) -> real {real}"),
            ),
            (Some(real), false, None) => push(
                "pid_file",
                CheckStatus::Warn,
                format!("no pid file; live pid {real}"),
            ),
            (None, _, _) => push("pid_file", CheckStatus::Info, "no service".to_string()),
        }

        if id.windows_using_our_pac {
            push("windows_pac", CheckStatus::Pass, id.auto_config_url.clone());
        } else if id.server_running {
            push(
                "windows_pac",
                CheckStatus::Warn,
                "Windows not pointed at our PAC".to_string(),
            );
        }

        if id.autostart_real.exists {
            push(
                "autostart",
                CheckStatus::Pass,
                format!("PACServer {}", id.autostart_real.state),
            );
        } else {
            push(
                "autostart",
                CheckStatus::Warn,
                "PACServer autostart task missing".to_string(),
            );
        }
        if id.autostart_gui.exists {
            push(
                "autostart",
                CheckStatus::Info,
                format!("WindowsSplitPAC (parallel GUI) {}", id.autostart_gui.state),
            );
        }

        let healthy = items
            .iter()
            .all(|it| matches!(it.status, CheckStatus::Pass | CheckStatus::Info));
        Self { items, healthy }
    }
}

/// The contract every split-routing engine implements.
///
/// The GUI talks to this interface, never to a specific core. That is what lets
/// the product ship with the minimal PAC engine today and drop in a heavier
/// mihomo engine later (subscriptions / TUN) without touching the UI flow —
/// the "layered" strategy from docs/RESEARCH-CLASH-VS-PAC-PLAN.md (L3).
pub trait SplitRoutingEngine {
    /// Read-only snapshot: which service is actually running and how healthy /
    /// in-sync it is (wraps `scripts/Get-ServiceIdentity.ps1`).
    fn identity(&self) -> Result<ServiceIdentity, String>;

    /// One-click apply: backup -> regenerate PAC -> (re)use service -> enable on
    /// Windows -> refresh WinINET -> verify -> rollback on failure. The ps1 only
    /// writes when `-Apply` is passed; the engine always passes `-Apply`.
    fn apply(&self, proxy_address: &str) -> Result<ApplyReport, String>;

    /// Turn split routing off and restore the previous Windows proxy settings.
    fn disable(&self) -> Result<(), String>;
}

/// Structured outcome of an apply run, parsed from `Apply-PacConfig.ps1` output.
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct ApplyReport {
    pub applied: bool,
    pub steps: Vec<String>,
    pub errors: Vec<String>,
    pub service: Option<ServiceSnapshot>,
    pub pac_ok: bool,
    pub healthz_ok: bool,
    pub windows_using_our_pac: bool,
    pub rules_drift: bool,
}

/// The PAC service snapshot embedded in an apply report.
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct ServiceSnapshot {
    pub running: bool,
    pub pid: Option<u32>,
    pub kind: String,
}

/// Default engine: drives the PAC pipeline through the PowerShell orchestrator.
pub struct PacEngine {
    root: PathBuf,
}

impl PacEngine {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    /// Absolute path to a script inside this repo's `scripts/` directory.
    pub fn script(&self, name: &str) -> String {
        self.root
            .join("scripts")
            .join(name)
            .to_string_lossy()
            .into_owned()
    }

    /// Parse the Apply-PacConfig JSON. The script keeps stdout pure JSON, but
    /// we also tolerate legacy stray log lines by falling back to the last
    /// non-empty line, so a stdout pollution regression cannot break the GUI.
    fn parse_apply_report(stdout: &str) -> Result<ApplyReport, String> {
        let trimmed = stdout.trim();
        if let Ok(report) = serde_json::from_str(trimmed) {
            return Ok(report);
        }
        if let Some(line) = trimmed.lines().rev().find(|line| !line.trim().is_empty()) {
            return serde_json::from_str(line)
                .map_err(|error| format!("Could not parse apply report: {error}"));
        }
        Err("Apply produced no JSON output".to_string())
    }

    /// Human-readable reason for a failed apply: prefer the structured errors
    /// the script writes to its result file on failure, then the tail of the
    /// captured stderr log, and only fall back to the generic message.
    fn apply_failure_reason(result_file: &std::path::Path, stderr_file: &std::path::Path) -> String {
        if let Ok(json) = fs::read_to_string(result_file)
            && let Ok(report) = Self::parse_apply_report(&json)
            && !report.errors.is_empty()
        {
            return report.errors.join("; ");
        }
        if let Ok(stderr) = fs::read_to_string(stderr_file) {
            let lines: Vec<&str> = stderr
                .lines()
                .map(str::trim)
                .filter(|line| !line.is_empty())
                .collect();
            let start = lines.len().saturating_sub(5);
            let tail = &lines[start..];
            if !tail.is_empty() {
                return format!("Apply-PacConfig.ps1 failed: {}", tail.join(" | "));
            }
        }
        "Apply-PacConfig.ps1 failed (no error details captured)".to_string()
    }

    /// Test one domain against the real PAC file via Test-PacDomain.ps1.
    /// Returns just the decision string (e.g. "PROXY 10.10.10.19:8080").
    /// Restart the local PAC service via Restart-PacServer.ps1.
    /// Restart Microsoft Edge once (method E): force it to re-read the PAC.
    pub fn restart_edge(&self) -> Result<String, String> {
        self.run_powershell("Restart-Browser.ps1", &[])
    }

    pub fn restart(&self) -> Result<String, String> {
        self.run_powershell("Restart-PacServer.ps1", &[])
    }

    pub fn test_domain(&self, domain: &str) -> Result<String, String> {
        let json = self.run_powershell("Test-PacDomain.ps1", &["-Domain", domain])?;
        let value: serde_json::Value = serde_json::from_str(&json)
            .map_err(|error| format!("Could not parse test result: {error}"))?;
        value
            .get("decision")
            .and_then(|d| d.as_str())
            .map(|s| s.to_string())
            .ok_or_else(|| "No decision returned by Test-PacDomain.ps1".to_string())
    }

    fn run_powershell(&self, name: &str, args: &[&str]) -> Result<String, String> {
        let output = Command::new("powershell.exe")
            .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"])
            .arg(self.script(name))
            .args(args)
            .stdin(Stdio::null())
            .env_remove("HTTP_PROXY")
            .env_remove("HTTPS_PROXY")
            .env_remove("http_proxy")
            .env_remove("https_proxy")
            .env_remove("ALL_PROXY")
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
}

impl SplitRoutingEngine for PacEngine {
    fn identity(&self) -> Result<ServiceIdentity, String> {
        let json = self.run_powershell("Get-ServiceIdentity.ps1", &[])?;
        serde_json::from_str(&json)
            .map_err(|error| format!("Could not parse service identity: {error}"))
    }

    fn apply(&self, proxy_address: &str) -> Result<ApplyReport, String> {
        // Use a result file + status() instead of output(): Apply-PacConfig can
        // start a background PAC service, and output() waits for EOF on stdout/
        // stderr pipes which a daemonized child may keep open -> GUI hang.
        let result_file = std::env::temp_dir().join("windows-split-pac-apply-result.json");
        let stderr_file = std::env::temp_dir().join("windows-split-pac-apply-stderr.log");
        let result_win = result_file.to_string_lossy().into_owned();
        // Capture stderr into a file (not a pipe) so the process still cannot
        // block the GUI, but the real PowerShell error survives for the UI.
        let stderr_handle = fs::File::create(&stderr_file)
            .map_err(|error| format!("Could not create stderr log: {error}"))?;
        let status = Command::new("powershell.exe")
            .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"])
            .arg(self.script("Apply-PacConfig.ps1"))
            .args([
                "-Apply",
                "-ProxyAddress",
                proxy_address,
                "-ResultFile",
                &result_win,
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::from(stderr_handle))
            .env_remove("HTTP_PROXY")
            .env_remove("HTTPS_PROXY")
            .env_remove("http_proxy")
            .env_remove("https_proxy")
            .env_remove("ALL_PROXY")
            .status()
            .map_err(|error| format!("Could not start Apply-PacConfig.ps1: {error}"))?;
        if !status.success() {
            return Err(Self::apply_failure_reason(&result_file, &stderr_file));
        }
        let json = fs::read_to_string(&result_file)
            .map_err(|error| format!("Could not read apply result file: {error}"))?;
        Self::parse_apply_report(&json)
    }

    fn disable(&self) -> Result<(), String> {
        self.run_powershell("Disable-WindowsPac.ps1", &[])
            .map(|_| ())
    }
}

pub fn is_valid_proxy_address(value: &str) -> bool {
    let value = value.trim();
    let Some((host, port)) = value.rsplit_once(':') else {
        return false;
    };
    !host.is_empty()
        && !host.contains("://")
        && !host.contains(char::is_whitespace)
        && port.parse::<u16>().is_ok_and(|port| port > 0)
}

/// A dead-simple, flat routing model for the "one-click" product.
///
///   * `proxy`  -> these domains always go through the proxy  (`||domain`)
///   * `direct` -> these domains always go direct            (`@@||domain`)
///   * anything else -> smart GFWList default               (not listed)
///
/// This is the user-facing shape behind M1's "three buckets" UI and maps 1:1
/// onto the Adblock/GFWList syntax that scripts/Build-Pac.ps1 feeds to genpac.
#[derive(Debug, Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SimpleRules {
    pub proxy: Vec<String>,
    pub direct: Vec<String>,
}

impl SimpleRules {
    /// Parse the text of a user-rules.txt into the two explicit buckets.
    ///
    /// Accepted lines: `||domain` -> proxy ; `@@||domain` -> direct ;
    /// bare `domain` -> proxy (lazy-friendly). Everything else is ignored
    /// (`!`/`#` comments, blanks). Domains are trimmed, trailing slashes are
    /// stripped, and entries are de-duplicated + sorted.
    pub fn parse(text: &str) -> Self {
        let mut proxy: Vec<String> = Vec::new();
        let mut direct: Vec<String> = Vec::new();
        for raw in text.lines() {
            let line = raw.trim();
            if line.is_empty() || line.starts_with('!') || line.starts_with('#') {
                continue;
            }
            let (bucket, rest) = if let Some(r) = line.strip_prefix("@@||") {
                (&mut direct, r)
            } else if let Some(r) = line.strip_prefix("||") {
                (&mut proxy, r)
            } else {
                (&mut proxy, line)
            };
            let domain = rest.trim().trim_end_matches('/').trim();
            if domain.is_empty() || domain.contains("://") || domain.contains(char::is_whitespace) {
                continue;
            }
            if !bucket.contains(&domain.to_string()) {
                bucket.push(domain.to_string());
            }
        }
        proxy.sort();
        direct.sort();
        Self { proxy, direct }
    }

    /// Build rules directly from the two bucket text areas the GUI edits.
    /// Every non-empty line is treated as a bare domain in that bucket; whitespace
    /// / weird lines are dropped and entries de-duplicated + sorted.
    pub fn from_bucket_text(proxy_text: &str, direct_text: &str) -> Self {
        let proxied = proxy_text
            .lines()
            .map(|l| format!("||{}", l.trim()))
            .collect::<Vec<_>>()
            .join("\n");
        let directed = direct_text
            .lines()
            .map(|l| format!("@@||{}", l.trim()))
            .collect::<Vec<_>>()
            .join("\n");
        Self::parse(&format!("{proxied}\n{directed}"))
    }

    /// Extract a usable rule domain from arbitrary user input (a full URL,
    /// bare domain, IP:port, userinfo URL, trailing slash/query, etc.).
    ///
    /// Examples:
    ///   "https://www.example.com/path?x=1" -> Some("example.com")
    ///   "example.com"                       -> Some("example.com")
    ///   "http://192.168.1.1:8080/"          -> Some("192.168.1.1")
    ///   "not a domain"                      -> None
    pub fn extract_domain(input: &str) -> Option<String> {
        let trimmed = input.trim();
        if trimmed.is_empty() {
            return None;
        }
        let after_scheme = trimmed
            .split_once("://")
            .map(|(_, rest)| rest)
            .unwrap_or(trimmed);
        let after_userinfo = after_scheme
            .rsplit_once('@')
            .map(|(_, rest)| rest)
            .unwrap_or(after_scheme);
        let host = after_userinfo
            .split(['/', '?', '#'])
            .next()
            .unwrap_or(after_userinfo)
            .trim();
        let host = host
            .rsplit_once(':')
            .map(|(h, _)| h)
            .unwrap_or(host)
            .trim()
            .trim_end_matches('.')
            .to_lowercase();
        if host.is_empty()
            || host.contains(char::is_whitespace)
            || host.contains("://")
            || !host.contains('.')
            || !host
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-'))
        {
            return None;
        }
        Some(host.strip_prefix("www.").unwrap_or(&host).to_string())
    }

    /// Serialize back to the user-rules.txt format genpac understands.
    pub fn render(&self) -> String {
        let mut out = String::new();
        out.push_str("! Custom proxy rules (Adblock Plus / GFWList syntax)\n");
        out.push_str("! Lines beginning with ! are comments.\n");
        out.push_str("!\n");
        out.push_str("! \u{1f310} Send a domain through the proxy:\n");
        out.push_str("! ||example.com\n");
        out.push_str("! \u{1f3e0} Keep a domain direct even if GFWList matches it:\n");
        out.push_str("! @@||example.com\n");
        for d in &self.proxy {
            out.push_str(&format!("||{}\n", d));
        }
        for d in &self.direct {
            out.push_str(&format!("@@||{}\n", d));
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::{
        ApplyReport, CheckStatus, Diagnostics, PacEngine, ServerKind, ServiceIdentity, SimpleRules,
        is_valid_proxy_address,
    };
    use std::fs;

    #[test]
    fn accepts_normal_lan_proxy_addresses() {
        assert!(is_valid_proxy_address("192.168.1.100:8080"));
        assert!(is_valid_proxy_address("10.0.0.5:3128"));
    }

    #[test]
    fn rejects_incomplete_or_invalid_proxy_addresses() {
        assert!(!is_valid_proxy_address(""));
        assert!(!is_valid_proxy_address("http://127.0.0.1:8080"));
        assert!(!is_valid_proxy_address("127.0.0.1"));
        assert!(!is_valid_proxy_address("127.0.0.1:0"));
    }

    #[test]
    fn parses_service_identity_json() {
        let json = r#"{
            "server_running": true,
            "server_kind": "real_serve_pac",
            "pid": 30572,
            "pid_file_matches": false,
            "pid_file_value": 28940,
            "port": 8765,
            "pac_url": "http://127.0.0.1:8765/proxy.pac",
            "pac_http_ok": true,
            "pac_proxy": "PROXY 10.10.10.19:8080",
            "server_cmd": "pythonw.exe serve_pac.py",
            "auto_config_url": "http://127.0.0.1:8765/proxy.pac",
            "proxy_enable": false,
            "proxy_server": "10.10.10.19:8080",
            "proxy_override": "<local>",
            "auto_detect": false,
            "windows_using_our_pac": true,
            "autostart_real": {"exists": true, "name": "PACServer", "state": "Ready"},
            "autostart_gui": {"exists": false, "name": "WindowsSplitPAC", "state": "Not present"},
            "rule_file_diff": {"online_rules": 5, "gui_rules": 0, "in_sync": false, "online_file": "C:\\proxy\\user-rules.txt", "repo_file": "rules\\user-rules.txt"}
        }"#;
        let id: ServiceIdentity = serde_json::from_str(json).expect("parse identity");
        assert_eq!(id.server_kind, ServerKind::RealServePac);
        assert_eq!(id.pid, Some(30572));
        assert!(id.real_service_active());
        assert!(id.rules_out_of_sync());
        assert_eq!(id.service_label(), "real (serve_pac.py)");
        assert!(id.autostart_real.exists);
    }

    #[test]
    fn defaults_missing_fields_gracefully() {
        // An empty object should still deserialize (all fields have defaults).
        let id: ServiceIdentity = serde_json::from_str("{}").expect("parse empty");
        assert_eq!(id.server_kind, ServerKind::None);
        assert!(!id.real_service_active());
        assert!(!id.rules_out_of_sync());
    }

    #[test]
    fn parses_apply_report_json() {
        // Shape produced by scripts/Apply-PacConfig.ps1 (dry-run and applied).
        let json = r#"{
            "applied": false,
            "steps": ["planned:generate-pac", "planned:enable-windows"],
            "errors": [],
            "service": {"running": true, "pid": 8808, "kind": "real_serve_pac"},
            "pac_ok": true,
            "healthz_ok": true,
            "windows_using_our_pac": true,
            "rules_drift": true
        }"#;
        let report: ApplyReport = serde_json::from_str(json).expect("parse apply report");
        assert!(!report.applied);
        assert_eq!(report.steps.len(), 2);
        assert!(report.healthz_ok);
        assert!(report.rules_drift);
        let svc = report.service.expect("service snapshot present");
        assert_eq!(svc.pid, Some(8808));
    }

    #[test]
    fn apply_failure_reason_prefers_structured_errors() {
        // On failure the script writes the result file with errors filled in;
        // the engine must surface those instead of the generic message.
        let dir = std::env::temp_dir();
        let result_file = dir.join("windows-split-pac-test-apply-result.json");
        let stderr_file = dir.join("windows-split-pac-test-apply-stderr.log");
        fs::write(
            &result_file,
            r#"{"applied":false,"steps":["ok:backup"],"errors":["generate-pac: genpac not found"],"service":null,"pac_ok":false,"healthz_ok":false,"windows_using_our_pac":false,"rules_drift":false}"#,
        )
        .unwrap();
        fs::write(&stderr_file, "").unwrap();
        assert_eq!(
            PacEngine::apply_failure_reason(&result_file, &stderr_file),
            "generate-pac: genpac not found"
        );

        // Without a result file, the stderr tail is used.
        fs::remove_file(&result_file).unwrap();
        fs::write(&stderr_file, "\nline1\nline2\n").unwrap();
        let reason = PacEngine::apply_failure_reason(&result_file, &stderr_file);
        assert!(reason.contains("line1 | line2"), "unexpected: {reason}");

        // With nothing captured at all, fall back to a generic message.
        fs::remove_file(&stderr_file).unwrap();
        assert!(PacEngine::apply_failure_reason(&result_file, &stderr_file)
            .starts_with("Apply-PacConfig.ps1 failed"));
    }

    #[test]
    fn pac_engine_resolves_scripts_relative_to_root() {
        // Compare path COMPONENTS so the assertion holds on both / and \ hosts.
        let engine = PacEngine::new("/repo/windows-split-pac");
        assert!(std::path::Path::new(&engine.script("Apply-PacConfig.ps1"))
            .ends_with("windows-split-pac/scripts/Apply-PacConfig.ps1"));
        assert!(std::path::Path::new(&engine.script("Get-ServiceIdentity.ps1"))
            .ends_with("windows-split-pac/scripts/Get-ServiceIdentity.ps1"));
    }

    #[test]
    fn simple_rules_three_bucket_roundtrip() {
        let text = "! comment\n\n||mrds66.com\n@@||baidu.com/\n||jcomic.net\nbad :with:space\n# hash comment\n";
        let rules = SimpleRules::parse(text);
        assert_eq!(
            rules.proxy,
            vec!["jcomic.net".to_string(), "mrds66.com".to_string()]
        );
        assert_eq!(rules.direct, vec!["baidu.com".to_string()]);

        let rendered = rules.render();
        assert!(rendered.contains("||mrds66.com"));
        assert!(rendered.contains("@@||baidu.com"));
        assert!(!rendered.contains("jcomic?"));
        // Rendering is stable: parsing the render gives the same model.
        assert_eq!(SimpleRules::parse(&rendered), rules);
    }

    #[test]
    fn simple_rules_from_bucket_text_sorts_and_filters() {
        let r = SimpleRules::from_bucket_text("b.com\n  a.com\nbad with space\n\n", "x.com/");
        assert_eq!(r.proxy, vec!["a.com".to_string(), "b.com".to_string()]);
        assert_eq!(r.direct, vec!["x.com".to_string()]);
    }

    #[test]
    fn service_identity_parses_healthz_fields() {
        let id: ServiceIdentity = serde_json::from_str(
            r#"{"server_running":true,"healthz_ok":true,"healthz_pid":33364}"#,
        )
        .expect("parse");
        assert!(id.healthz_ok);
        assert_eq!(id.healthz_pid, Some(33364));
    }

    #[test]
    fn diagnostics_flags_stale_pid_and_missing_healthz() {
        let id: ServiceIdentity = serde_json::from_str(
            r#"{
            "server_running": true, "server_kind": "real_serve_pac", "pid": 8808,
            "pid_file_matches": false, "pid_file_value": 28940,
            "pac_http_ok": true, "healthz_ok": false, "healthz_pid": null,
            "windows_using_our_pac": true,
            "autostart_real": {"exists": true, "name": "PACServer", "state": "Ready"},
            "autostart_gui": {"exists": false, "name": "WindowsSplitPAC", "state": "Not present"},
            "rule_file_diff": {"online_rules": 5, "gui_rules": 0, "in_sync": false}
        }"#,
        )
        .expect("parse");
        let d = Diagnostics::from_identity(&id);
        assert!(!d.healthy);
        let pid_item = d
            .items
            .iter()
            .find(|i| i.key == "pid_file")
            .expect("pid_file item");
        assert_eq!(pid_item.status, CheckStatus::Warn);
        let hz = d
            .items
            .iter()
            .find(|i| i.key == "healthz")
            .expect("healthz item");
        assert_eq!(hz.status, CheckStatus::Warn);
    }

    #[test]
    fn diagnostics_all_green_for_healthy_service() {
        let id: ServiceIdentity = serde_json::from_str(
            r#"{
            "server_running": true, "server_kind": "real_serve_pac", "pid": 33364,
            "pid_file_matches": true, "pid_file_value": 33364,
            "pac_http_ok": true, "healthz_ok": true, "healthz_pid": 33364,
            "windows_using_our_pac": true,
            "autostart_real": {"exists": true, "name": "PACServer", "state": "Running"},
            "autostart_gui": {"exists": false, "name": "WindowsSplitPAC", "state": "Not present"},
            "rule_file_diff": {"online_rules": 5, "gui_rules": 5, "in_sync": true}
        }"#,
        )
        .expect("parse");
        let d = Diagnostics::from_identity(&id);
        assert!(d.healthy, "expected all-pass: {:?}", d.items);
    }

    #[test]
    fn parses_apply_report_with_diagnostic_prefix() {
        // Legacy/stdout-pollution regression: log lines before JSON must still parse.
        let stdout = "Preflight: rules=True ...\n[APPLY] Backed up rules\n{\"applied\":true,\"steps\":[],\"errors\":[]}\n";
        let report = PacEngine::parse_apply_report(stdout).expect("parse prepended json");
        assert!(report.applied);

        let clean = "{\"applied\":false,\"steps\":[],\"errors\":[]}";
        let clean_report = PacEngine::parse_apply_report(clean).expect("parse clean json");
        assert!(!clean_report.applied);
    }

    #[test]
    #[ignore = "E2E: requires Windows PowerShell interop; run with: cargo test -- --ignored"]
    fn engine_apply_isolated_e2e_runs_actual_powershell() {
        use std::{
            fs,
            path::PathBuf,
            process::{Command, Stdio},
        };

        let probe = Command::new("powershell.exe")
            .args([
                "-NoProfile",
                "-Command",
                "$PSVersionTable.PSVersion.ToString()",
            ])
            .output();
        let Ok(probe) = probe else {
            eprintln!("SKIP: powershell.exe unavailable");
            return;
        };
        if !probe.status.success() {
            eprintln!("SKIP: powershell.exe probe failed");
            return;
        }

        let core_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let root = core_dir
            .parent()
            .and_then(|p| p.parent())
            .map(|p| p.to_path_buf())
            .unwrap_or_else(|| core_dir.clone());
        let script_linux = root.join("scripts").join("Apply-PacConfig.ps1");
        if !script_linux.exists() {
            eprintln!("SKIP: Apply-PacConfig.ps1 not found");
            return;
        }

        // Prefer the already-packaged copy on F: (Windows-local path -> no UNC
        // Start-Process mangling, same as the user's real VM/Windows scenario).
        let package_script =
            PathBuf::from("/mnt/f/WindowsSplitPAC-Verify/scripts/Apply-PacConfig.ps1");
        let script_arg = if package_script.exists() {
            r"F:\WindowsSplitPAC-Verify\scripts\Apply-PacConfig.ps1".to_string()
        } else if cfg!(target_os = "linux") {
            let out = Command::new("wslpath")
                .arg("-w")
                .arg(&script_linux)
                .output()
                .expect("wslpath");
            String::from_utf8_lossy(&out.stdout).trim().to_string()
        } else {
            script_linux.to_string_lossy().into_owned()
        };

        let temp_linux = PathBuf::from("/mnt/c/Windows/Temp/wsp-rust-engine-e2e");
        let temp_win = r"C:\Windows\Temp\wsp-rust-engine-e2e";
        let _ = fs::create_dir_all(&temp_linux);
        let rules_path = temp_linux.join("user-rules.txt");
        let pac_path = temp_linux.join("proxy.pac");
        fs::write(&rules_path, "||e2e-proxy.example\n@@||e2e-direct.example\n")
            .expect("write rules");
        fs::write(
            &pac_path,
            "function FindProxyForURL(url, host) { if (host == \"e2e-direct.example\") return \"DIRECT\"; return \"PROXY 127.0.0.1:9999\"; }\n",
        )
        .expect("write pac");

        let pac_win = format!(r"{temp_win}\proxy.pac");
        let rules_win = format!(r"{temp_win}\user-rules.txt");
        let port = "18898";

        // Defensive: kill anything still listening on the test port before the run.
        let _ = Command::new("powershell.exe")
            .args([
                "-NoProfile",
                "-Command",
                &format!(
                    "Get-NetTCPConnection -LocalPort {port} -State Listen -ErrorAction SilentlyContinue | ForEach-Object {{ Stop-Process -Id $_.OwningProcess -Force }}"
                ),
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();

        let result_file_linux = temp_linux.join("apply-result.json");
        let result_file_win = format!(r"{temp_win}\apply-result.json");
        let mut child = Command::new("powershell.exe")
            .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"])
            .arg(&script_arg)
            .args([
                "-Apply",
                "-Port",
                port,
                "-ProxyAddress",
                "127.0.0.1:9999",
                "-PacFile",
                &pac_win,
                "-RulesFile",
                &rules_win,
                "-RunDir",
                temp_win,
                "-ResultFile",
                &result_file_win,
                "-SkipWindows",
                "-SkipGenerate",
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::from(
                fs::File::create(temp_linux.join("apply.stdout.log")).expect("stdout log"),
            ))
            .stderr(Stdio::from(
                fs::File::create(temp_linux.join("apply.stderr.log")).expect("stderr log"),
            ))
            .env_remove("HTTP_PROXY")
            .env_remove("HTTPS_PROXY")
            .env_remove("http_proxy")
            .env_remove("https_proxy")
            .env_remove("ALL_PROXY")
            .spawn()
            .expect("run Apply-PacConfig");

        // WSL interop quirk: /init waits for a daemonized child (the temp PAC
        // server) to exit, so a watchdog kills the test-port listener after a
        // few seconds to let wait() return. On real Windows this is unnecessary.
        let killer_port = port.to_string();
        let killer = std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_secs(8));
            let _ = Command::new("powershell.exe")
                .args([
                    "-NoProfile",
                    "-Command",
                    &format!(
                        "Get-NetTCPConnection -LocalPort {killer_port} -State Listen -ErrorAction SilentlyContinue | ForEach-Object {{ Stop-Process -Id $_.OwningProcess -Force }}"
                    ),
                ])
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
        });
        let status = child.wait().expect("wait Apply-PacConfig");
        let _ = killer.join();

        assert!(status.success(), "Apply-PacConfig exited nonzero");
        let stdout = fs::read_to_string(&result_file_linux).expect("read result file");
        let report = PacEngine::parse_apply_report(&stdout).expect("parse apply report");
        assert!(report.applied, "applied flag; stdout={stdout}");
        assert!(report.pac_ok, "pac_ok; stdout={stdout}");
        assert!(report.healthz_ok, "healthz_ok; stdout={stdout}");
        assert!(report.errors.is_empty(), "errors: {:?}", report.errors);

        // Cleanup the isolated temp service and files.
        let _ = Command::new("powershell.exe")
            .args([
                "-NoProfile",
                "-Command",
                &format!(
                    "Get-NetTCPConnection -LocalPort {port} -State Listen -ErrorAction SilentlyContinue | ForEach-Object {{ Stop-Process -Id $_.OwningProcess -Force }}"
                ),
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        let _ = fs::remove_dir_all(&temp_linux);
    }

    #[test]
    fn extract_domain_from_arbitrary_input() {
        assert_eq!(
            SimpleRules::extract_domain("https://www.example.com/path?x=1"),
            Some("example.com".to_string())
        );
        assert_eq!(
            SimpleRules::extract_domain("example.com"),
            Some("example.com".to_string())
        );
        assert_eq!(
            SimpleRules::extract_domain("  http://sub.example.co.uk:8080/a "),
            Some("sub.example.co.uk".to_string())
        );
        assert_eq!(
            SimpleRules::extract_domain("ftp://user@host.example.net/"),
            Some("host.example.net".to_string())
        );
        assert_eq!(
            SimpleRules::extract_domain("192.168.1.1"),
            Some("192.168.1.1".to_string())
        );
        assert_eq!(SimpleRules::extract_domain(""), None);
        assert_eq!(
            SimpleRules::extract_domain("not a domain with spaces"),
            None
        );
    }
}
