<#
.SYNOPSIS
  push 前确保代理可用；端口不通时自动启动 dev-sidecar。

.DESCRIPTION
  国内直连 GitHub 不稳：push 常在「TCP 已连上但连不上 github.com」这一步失败。
  代理是 dev-sidecar（Electron 应用）提供的 HTTP 代理，监听 127.0.0.1:31181。

  ⚠ **端口能连 ≠ 代理能用**。dev-sidecar 进程在、端口也在听，但上游节点没连上时，
    git 会报 `Failed to connect to github.com port 443 via 127.0.0.1`——
    本机实测出现过端口 open 而 push 全败的情况。所以判定必须分两级：
    先 TCP，再**穿过代理发一次真实请求**，两级都过才算可用。

  ⚠ 本脚本**不改 git config**。代理通过环境变量传给 git（每次命令自己设），
    免得把本机代理地址固化进仓库配置，换机器或换网络时 git 直接不可用。

.PARAMETER Port
  代理监听的端口，默认 31181。

.PARAMETER ExePath
  dev-sidecar 可执行文件的完整路径。留空（默认）则用常用安装目录
  F:\ProgramFilesNoMove\dev-sidecar\dev-sidecar.exe；该文件不存在就**不拉起**，
  提示手动启动并退出 1。

.PARAMETER ProbeUrl
  端到端探测的目标地址，默认 https://github.com。必须是 https——
  只有 https 才会真正走 CONNECT，否则测的仍只是 TCP 连通。

.PARAMETER TimeoutSec
  端口起来后的等待秒数，默认 30。dev-sidecar 是 Electron 应用，冷启动偏慢。

.PARAMETER Quiet
  只输出错误，不打印步骤与提示。

.EXAMPLE
  # 发布流程里 push 之前先跑一次
  pwsh -File scripts/ensure-proxy.ps1
  $env:HTTPS_PROXY = 'http://127.0.0.1:31181'
  $env:HTTP_PROXY  = $env:HTTPS_PROXY
  git push origin main

  # 端口不对时
  pwsh -File scripts/ensure-proxy.ps1 -Port 7890

  # dev-sidecar 装在别处时
  pwsh -File scripts/ensure-proxy.ps1 -ExePath 'D:\tools\dev-sidecar\dev-sidecar.exe'

  # 探测目标换成别的站点
  pwsh -File scripts/ensure-proxy.ps1 -ProbeUrl 'https://registry.npmjs.org'

.NOTES
  退出码：0 = 代理可用；1 = 端口不通且拉不起 sidecar；2 = 端口在听但代理不通
  （通常要在 dev-sidecar 界面里选节点/打开开关，脚本无能为力）。
#>
[CmdletBinding()]
param(
  [int]$Port = 31181,
  # 留空则用下面的常用安装目录；只有确实装在别处时才用 -ExePath 指定
  [string]$ExePath,
  # 端到端探测目标：必须是 https，才能真正走 CONNECT 而不是只测 TCP
  [string]$ProbeUrl = 'https://github.com',
  # 端口起来后等多久（秒）。dev-sidecar 是 Electron，冷启动要几秒
  [int]$TimeoutSec = 30,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Write-Step($text) { if (-not $Quiet) { Write-Host "`n== $text" -ForegroundColor Cyan } }
function Write-Ok($text) { if (-not $Quiet) { Write-Host "   $text" -ForegroundColor Green } }
function Write-Warn2($text) { if (-not $Quiet) { Write-Host "   ! $text" -ForegroundColor Yellow } }

# TCP 探测。用 TcpClient 而不是 Test-NetConnection：后者每处要 1~2 秒，
# 而这里要在超时窗口里轮询多次。
function Test-TcpPort([int]$Port, [int]$TimeoutMs = 1500) {
  $client = [Net.Sockets.TcpClient]::new()
  try {
    $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
    if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
    $client.EndConnect($async)
    return $true
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

# 端到端探测：真正穿过代理访问一次 https。这一步才能区分
# 「端口在听」与「代理真的通」。
function Test-ProxyRequest([int]$Port, [string]$Url, [int]$TimeoutSec = 12) {
  try {
    $null = Invoke-WebRequest -Uri $Url -Proxy "http://127.0.0.1:$Port" `
      -Method Head -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
    return $true
  } catch {
    # GitHub 对 HEAD 可能回 405/403/404，但这说明**链路是通的**，同样算通过。
    # 除此之外只有"拿到过 HTTP 状态码"的错误才算通；502/503/504 表示代理连上了但上游没通，
    # 超时与 DNS 解析失败同理，都是代理不可用。
    $msg = $_.Exception.Message
    if ($msg -match '(?<!\d)(502|503|504)\b' -or
        $msg -match 'Bad Gateway|Service Unavailable|Gateway Time-out') {
      Write-Verbose "端到端探测：代理已连接但上游不通：$msg"
      return $false
    }
    if ($msg -match 'timed out|超时|could not be resolved|无法解析|name resolution|DNS') {
      Write-Verbose "端到端探测：超时或 DNS 失败：$msg"
      return $false
    }
    if ($msg -match 'unable to connect|actively refused|tunnel|proxy|socket|SSL|TLS|无法连接') {
      Write-Verbose "端到端探测失败（连接类）：$msg"
      return $false
    }
    Write-Verbose "端到端探测收到非连接类响应（视为链路通）：$msg"
    return $true
  }
}

$proxyUrl = "http://127.0.0.1:$Port"

Write-Step "检查代理 127.0.0.1:$Port"

if (Test-TcpPort $Port) {
  Write-Ok "端口在监听"
} else {
  Write-Warn2 "端口不通，检查 dev-sidecar 是否在运行"
  $running = Get-Process -Name 'dev-sidecar' -ErrorAction SilentlyContinue
  if (-not $running) {
    # 只认一个常用安装目录。找不到就不拉起，也不去 PATH 或注册表里猜。
    if (-not $ExePath) {
      $ExePath = 'F:\ProgramFilesNoMove\dev-sidecar\dev-sidecar.exe'
    }
    if (-not (Test-Path -LiteralPath $ExePath)) {
      Write-Host "   $ExePath 不存在，代理无法自动启动。" -ForegroundColor Red
      Write-Host "   请手动启动 dev-sidecar 后重跑本脚本，或用 -ExePath 指定路径。" -ForegroundColor Red
      exit 1
    }
    Write-Step "启动 dev-sidecar"
    Start-Process -FilePath $ExePath | Out-Null
    Write-Ok "已拉起 $ExePath"
  } else {
    Write-Ok "dev-sidecar 进程在（PID $($running[0].Id)），但端口没开——多半是代理开关没打开"
  }

  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $up = $false
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 800
    if (Test-TcpPort $Port) { $up = $true; break }
  }
  if (-not $up) {
    Write-Host "   等了 $TimeoutSec 秒端口仍未监听。" -ForegroundColor Red
    exit 1
  }
  Write-Ok "端口已监听"
}

Write-Step '穿过代理做一次真实请求'

if (-not (Test-ProxyRequest $Port $ProbeUrl)) {
  Write-Host "   端口在听，但代理连不上 $ProbeUrl。" -ForegroundColor Red
  Write-Host "   多半是 dev-sidecar 里没选节点或开关没打开——这步只能手动处理，" -ForegroundColor Red
  Write-Host "   界面处理完再重跑本脚本。" -ForegroundColor Red
  exit 2
}

Write-Ok "代理可用"
if (-not $Quiet) {
  Write-Host "`n   git 需要自己带上环境变量（脚本不改 git config）：" -ForegroundColor Cyan
  Write-Host "   `$env:HTTPS_PROXY = '$proxyUrl'"
  Write-Host "   `$env:HTTP_PROXY  = `$env:HTTPS_PROXY"
}
exit 0
