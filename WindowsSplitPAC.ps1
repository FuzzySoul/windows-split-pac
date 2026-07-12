[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`"")
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$root = $PSScriptRoot
$pacUrl = 'http://127.0.0.1:8765/proxy.pac'
$texts = @{
    '简体中文' = @{
        Title = 'Windows Split PAC'; Subtitle = 'GFWList 智能分流 | 简单模式与极客模式'; Language = '界面语言'
        Simple = '简单操作'; Advanced = '进阶操作'; Step1 = '1. 准备环境'; Step2 = '2. 填写 HTTP 代理地址'; Step3 = '3. 一键生成并启动'
        Install = '准备 Python 与 genpac'; GenerateStart = '生成 PAC 并启动'; EditRules = '编辑自定义规则'; OpenSettings = '复制 PAC 地址并打开系统设置'
        ProxyHint = '示例：192.168.1.100:8080（不要写 http://）'; SafeHint = '此工具不会自动修改 Windows 代理设置。生成后请在系统设置中手动启用“使用设置脚本”。'
        StatusReady = '就绪：先准备环境，然后输入代理地址。'; AdvancedHint = '每个按钮都对应仓库中的一个可审查脚本。'; Start = '只启动服务'; Stop = '停止服务'; Check = '检查服务'; Autostart = '启用开机自启'; RemoveAutostart = '移除开机自启'
        Command = '对应命令'; Log = '运行日志'; ConfirmAutostart = '这会创建名为 WindowsSplitPAC 的登录后启动任务，不会修改 Windows 代理设置。是否继续？'; ValidProxy = '请输入有效的 HTTP 代理地址，例如 192.168.1.100:8080。'
        BuildFirst = '请先成功生成 PAC 文件，再启动服务。'; CopyDone = 'PAC 地址已复制到剪贴板，系统代理设置已打开。'; HealthOk = '服务健康检查通过。'; HealthFail = '服务未响应。请先生成并启动 PAC 服务。'
        NeedDependencies = '请先点击“准备 Python 与 genpac”。'; RuleTitle = '自定义规则'; RuleHelp = '一行一条规则。例如 ||example.com 表示强制代理；@@||example.com 表示强制直连。'
    }
    'English' = @{
        Title = 'Windows Split PAC'; Subtitle = 'GFWList smart routing | Simple mode and Geek mode'; Language = 'Language'
        Simple = 'Simple'; Advanced = 'Advanced'; Step1 = '1. Prepare'; Step2 = '2. Enter HTTP proxy address'; Step3 = '3. Generate and start'
        Install = 'Prepare Python and genpac'; GenerateStart = 'Generate PAC and start'; EditRules = 'Edit custom rules'; OpenSettings = 'Copy PAC URL and open Windows Settings'
        ProxyHint = 'Example: 192.168.1.100:8080 (do not include http://)'; SafeHint = 'This tool never changes Windows proxy settings automatically. Enable “Use setup script” yourself after generation.'
        StatusReady = 'Ready: prepare the environment, then enter a proxy address.'; AdvancedHint = 'Every button maps to a reviewable script in this repository.'; Start = 'Start service only'; Stop = 'Stop service'; Check = 'Check service'; Autostart = 'Enable autostart'; RemoveAutostart = 'Remove autostart'
        Command = 'Command'; Log = 'Activity log'; ConfirmAutostart = 'This creates the WindowsSplitPAC logon task and does not change Windows proxy settings. Continue?'; ValidProxy = 'Enter a valid HTTP proxy address, for example 192.168.1.100:8080.'
        BuildFirst = 'Generate a PAC file successfully before starting the service.'; CopyDone = 'The PAC URL was copied to the clipboard and Windows proxy settings were opened.'; HealthOk = 'PAC server health check passed.'; HealthFail = 'PAC server did not respond. Generate and start it first.'
        NeedDependencies = 'Run “Prepare Python and genpac” first.'; RuleTitle = 'Custom rules'; RuleHelp = 'One rule per line. ||example.com forces proxy; @@||example.com forces direct.'
    }
}

function New-Label([string]$text, [int]$x, [int]$y, [int]$width, [int]$height = 24, [float]$size = 10, [bool]$bold = $false) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text; $label.Location = New-Object System.Drawing.Point($x, $y); $label.Size = New-Object System.Drawing.Size($width, $height)
    $style = if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $label.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', $size, $style)
    $label.ForeColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
    return $label
}

function New-Button([int]$x, [int]$y, [int]$width, [int]$height = 38) {
    $button = New-Object System.Windows.Forms.Button
    $button.Location = New-Object System.Drawing.Point($x, $y); $button.Size = New-Object System.Drawing.Size($width, $height)
    $button.FlatStyle = 'Flat'; $button.FlatAppearance.BorderSize = 0
    $button.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
    $button.BackColor = [System.Drawing.Color]::FromArgb(8, 145, 178); $button.ForeColor = [System.Drawing.Color]::White
    return $button
}

function Invoke-Tool([string]$scriptName, [string[]]$arguments = @()) {
    $scriptPath = Join-Path $root "scripts\$scriptName"
    if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Tool script not found: $scriptPath" }
    $activityLog.AppendText("`r`n> $scriptName $($arguments -join ' ')`r`n")
    $result = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @arguments 2>&1
    foreach ($line in $result) { $activityLog.AppendText("$line`r`n") }
    if ($LASTEXITCODE -ne 0) { throw "Exit code: $LASTEXITCODE" }
}

function Set-Status([string]$message, [bool]$isError = $false) {
    $statusLabel.Text = $message
    $statusLabel.ForeColor = if ($isError) { [System.Drawing.Color]::FromArgb(251, 113, 133) } else { [System.Drawing.Color]::FromArgb(94, 234, 212) }
}

$form = New-Object System.Windows.Forms.Form
$form.ClientSize = New-Object System.Drawing.Size(790, 640)
$form.MinimumSize = New-Object System.Drawing.Size(806, 679)
$form.Text = 'Windows Split PAC'
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$title = New-Label '' 26 20 470 34 18 $true
$subtitle = New-Label '' 28 55 520 25 9
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(103, 232, 249)
$languageLabel = New-Label '' 600 24 80 22 9 $true
$languageLabel.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$languagePicker = New-Object System.Windows.Forms.ComboBox
$languagePicker.Location = New-Object System.Drawing.Point(600, 48); $languagePicker.Size = New-Object System.Drawing.Size(155, 28)
$languagePicker.DropDownStyle = 'DropDownList'; [void]$languagePicker.Items.Add('简体中文'); [void]$languagePicker.Items.Add('English'); $languagePicker.SelectedIndex = 0
$form.Controls.AddRange(@($title, $subtitle, $languageLabel, $languagePicker))

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(24, 95); $tabs.Size = New-Object System.Drawing.Size(742, 515)
$simpleTab = New-Object System.Windows.Forms.TabPage; $simpleTab.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
$advancedTab = New-Object System.Windows.Forms.TabPage; $advancedTab.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
[void]$tabs.TabPages.Add($simpleTab); [void]$tabs.TabPages.Add($advancedTab); $form.Controls.Add($tabs)

$step1 = New-Label '' 25 25 300 28 12 $true; $step2 = New-Label '' 25 94 350 28 12 $true; $step3 = New-Label '' 25 195 350 28 12 $true
$installButton = New-Button 25 55 260; $proxyBox = New-Object System.Windows.Forms.TextBox
$proxyBox.Location = New-Object System.Drawing.Point(25, 128); $proxyBox.Size = New-Object System.Drawing.Size(410, 28); $proxyBox.Font = New-Object System.Drawing.Font('Consolas', 10)
$proxyHint = New-Label '' 25 160 560 25 9; $proxyHint.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$generateButton = New-Button 25 230 260 45; $editRulesButton = New-Button 300 230 180 45; $settingsButton = New-Button 25 293 455 38
$safeHint = New-Label '' 25 345 650 48 9; $safeHint.ForeColor = [System.Drawing.Color]::FromArgb(250, 204, 21)
$simpleTab.Controls.AddRange(@($step1, $step2, $step3, $installButton, $proxyBox, $proxyHint, $generateButton, $editRulesButton, $settingsButton, $safeHint))

$advancedHint = New-Label '' 25 25 650 42 10; $advancedHint.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$startButton = New-Button 25 82 175; $stopButton = New-Button 214 82 175; $checkButton = New-Button 403 82 175
$autostartButton = New-Button 25 132 270; $removeAutostartButton = New-Button 309 132 270
$commandLabel = New-Label '' 25 195 250 24 11 $true
$commandBox = New-Object System.Windows.Forms.TextBox
$commandBox.Location = New-Object System.Drawing.Point(25, 225); $commandBox.Size = New-Object System.Drawing.Size(670, 60); $commandBox.Multiline = $true; $commandBox.ReadOnly = $true; $commandBox.ScrollBars = 'Vertical'; $commandBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$logLabel = New-Label '' 25 305 250 24 11 $true
$activityLog = New-Object System.Windows.Forms.TextBox
$activityLog.Location = New-Object System.Drawing.Point(25, 335); $activityLog.Size = New-Object System.Drawing.Size(670, 115); $activityLog.Multiline = $true; $activityLog.ReadOnly = $true; $activityLog.ScrollBars = 'Vertical'; $activityLog.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42); $activityLog.ForeColor = [System.Drawing.Color]::FromArgb(203, 213, 225); $activityLog.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$advancedTab.Controls.AddRange(@($advancedHint, $startButton, $stopButton, $checkButton, $autostartButton, $removeAutostartButton, $commandLabel, $commandBox, $logLabel, $activityLog))

$statusLabel = New-Label '' 26 614 735 22 9 $true; $form.Controls.Add($statusLabel)

function Update-Language {
    $t = $texts[$languagePicker.SelectedItem]
    $form.Text = $t.Title; $title.Text = $t.Title; $subtitle.Text = $t.Subtitle; $languageLabel.Text = $t.Language
    $simpleTab.Text = $t.Simple; $advancedTab.Text = $t.Advanced; $step1.Text = $t.Step1; $step2.Text = $t.Step2; $step3.Text = $t.Step3
    $installButton.Text = $t.Install; $generateButton.Text = $t.GenerateStart; $editRulesButton.Text = $t.EditRules; $settingsButton.Text = $t.OpenSettings
    $proxyHint.Text = $t.ProxyHint; $safeHint.Text = $t.SafeHint; $advancedHint.Text = $t.AdvancedHint
    $startButton.Text = $t.Start; $stopButton.Text = $t.Stop; $checkButton.Text = $t.Check; $autostartButton.Text = $t.Autostart; $removeAutostartButton.Text = $t.RemoveAutostart
    $commandLabel.Text = $t.Command; $logLabel.Text = $t.Log
    $commandBox.Text = ".\scripts\Build-Pac.ps1 -ProxyAddress '192.168.1.100:8080'`r`n.\scripts\Start-PacServer.ps1`r`n.\scripts\Test-Package.ps1"
    Set-Status $t.StatusReady
}

$languagePicker.Add_SelectedIndexChanged({ Update-Language })
$installButton.Add_Click({ try { Invoke-Tool 'Install-Dependencies.ps1'; Set-Status 'genpac is ready.' } catch { Set-Status $_.Exception.Message $true } })
$generateButton.Add_Click({
    $t = $texts[$languagePicker.SelectedItem]
    if ($proxyBox.Text.Trim() -notmatch '^[^\s:]+:\d+$') { [System.Windows.Forms.MessageBox]::Show($t.ValidProxy, $t.Title, 'OK', 'Warning'); return }
    try { Invoke-Tool 'Build-Pac.ps1' @('-ProxyAddress', $proxyBox.Text.Trim()); Invoke-Tool 'Start-PacServer.ps1'; Set-Status "$($t.GenerateStart): $pacUrl" } catch { Set-Status $_.Exception.Message $true }
})
$editRulesButton.Add_Click({ Start-Process notepad.exe (Join-Path $root 'rules\user-rules.txt') })
$settingsButton.Add_Click({ [System.Windows.Forms.Clipboard]::SetText($pacUrl); Start-Process 'ms-settings:network-proxy'; Set-Status $texts[$languagePicker.SelectedItem].CopyDone })
$startButton.Add_Click({ try { Invoke-Tool 'Start-PacServer.ps1'; Set-Status "PAC: $pacUrl" } catch { Set-Status $_.Exception.Message $true } })
$stopButton.Add_Click({ try { Invoke-Tool 'Stop-PacServer.ps1'; Set-Status 'PAC server stopped.' } catch { Set-Status $_.Exception.Message $true } })
$checkButton.Add_Click({ try { $response = Invoke-WebRequest -UseBasicParsing -Uri $pacUrl -TimeoutSec 3; if ($response.StatusCode -eq 200) { Set-Status $texts[$languagePicker.SelectedItem].HealthOk } } catch { Set-Status $texts[$languagePicker.SelectedItem].HealthFail $true } })
$autostartButton.Add_Click({ $t = $texts[$languagePicker.SelectedItem]; if ([System.Windows.Forms.MessageBox]::Show($t.ConfirmAutostart, $t.Title, 'YesNo', 'Question') -eq 'Yes') { try { Invoke-Tool 'Install-Autostart.ps1'; Set-Status 'Autostart task installed.' } catch { Set-Status $_.Exception.Message $true } } })
$removeAutostartButton.Add_Click({ try { Invoke-Tool 'Uninstall-Autostart.ps1'; Set-Status 'Autostart task removed.' } catch { Set-Status $_.Exception.Message $true } })

Update-Language
[void]$form.ShowDialog()
