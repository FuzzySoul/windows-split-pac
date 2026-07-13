use serde::{Deserialize, Serialize};

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

pub fn is_valid_proxy_address(value: &str) -> bool {
    let value = value.trim();
    let Some((host, port)) = value.rsplit_once(':') else { return false; };
    !host.is_empty()
        && !host.contains("://")
        && !host.contains(char::is_whitespace)
        && port.parse::<u16>().is_ok_and(|port| port > 0)
}

#[cfg(test)]
mod tests {
    use super::is_valid_proxy_address;

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
}
