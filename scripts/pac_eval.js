// Windows JScript evaluator for a PAC file.
// Usage:
//   cscript //nologo //E:JScript pac_eval.js <pac-file> <domain>
// Prints the decision string from FindProxyForURL("http://<domain>/", "<domain>").
var fso = new ActiveXObject("Scripting.FileSystemObject");
var pacPath = WScript.Arguments(0);
var domain = WScript.Arguments(1);

if (!fso.FileExists(pacPath)) {
    WScript.Echo("PAC_NOT_FOUND:" + pacPath);
    WScript.Quit(2);
}
var file = fso.OpenTextFile(pacPath, 1);
var pacText = file.ReadAll();
file.Close();

// --- PAC predefined-function polyfills (domain-oriented, read-only) ---
function isPlainHostName(host) {
    return String(host).indexOf(".") === -1;
}
function dnsDomainIs(host, domain) {
    var h = String(host).toLowerCase();
    var d = String(domain).toLowerCase();
    return h === d || (h.length > d.length && h.indexOf("." + d) === h.length - d.length - 1);
}
function dnsDomainLevels(host) {
    return String(host).split(".").length - 1;
}
function shExpMatch(str, pattern) {
    var p = String(pattern).replace(/\*/g, ".*").replace(/\?/g, ".");
    return new RegExp("^" + p + "$").test(String(str));
}
function isInNet(host, pattern, mask) {
    return false; // domain-oriented tests: do not resolve/route IP rules
}
function dnsResolve(host) {
    return "";
}
function myIpAddress() {
    return "127.0.0.1";
}
function weekdayRange() {
    return false;
}
function dateRange() {
    return false;
}
function timeRange() {
    return false;
}
function alert(msg) {
    WScript.Echo(msg);
}

try {
    eval(pacText);
    if (typeof FindProxyForURL !== "function") {
        WScript.Echo("NO_FINDPROXYFORURL");
        WScript.Quit(3);
    }
    var result = FindProxyForURL("http://" + domain + "/", domain);
    WScript.Echo(String(result));
} catch (e) {
    WScript.Echo("PAC_EVAL_ERROR:" + e.message);
    WScript.Quit(4);
}