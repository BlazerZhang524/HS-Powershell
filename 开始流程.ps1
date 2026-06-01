#Admin check
$CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($CurrentUser)
$IsAdmin = $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "当前不是管理员权限，正在尝试以管理员权限重新启动脚本..."

    Start-Process powershell.exe -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`""
    ) -Verb RunAs

    exit
}
$Targetpath="C:\temp"
Write-Host "开始复制安装文件到 C:\temp"
Write-Host ""
New-Item -Path $Targetpath -ItemType Directory -Force
Copy-Item -Path "$PSScriptRoot\*" -Destination $Targetpath -Recurse -Force
Write-Host "复制完成，开始执行装机脚本"
Write-Host ""
$Installscript = Join-Path $Targetpath "装软件.ps1"
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

& $Installscript

