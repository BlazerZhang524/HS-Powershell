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

Set-ExecutionPolicy RemoteSigned -Scope Process -Force

# Log settings
$Script:LogDir = "C:\temp\InstallLogs"

if (!(Test-Path $Script:LogDir)) {
    New-Item -Path $Script:LogDir -ItemType Directory -Force | Out-Null
}

$Script:LogFile = Join-Path $Script:LogDir ("LaptopSetup_{0}_{1}.log" -f $env:COMPUTERNAME, (Get-Date -Format "yyyyMMdd_HHmmss"))

# 全局安装失败标记：任意软件安装失败后，最后不清理 C:\temp，也不自动重启
$Script:InstallFailed = $false
$Script:FailedSoftwareList = @()

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "$Time [$Level] $Message"

    Add-Content -Path $Script:LogFile -Value $Line -Encoding UTF8
}

function Register-InstallFailure {
    param(
        [string]$SoftwareName,
        [string]$Reason = ""
    )

    $Script:InstallFailed = $true

    if ($Reason) {
        $Item = "$SoftwareName - $Reason"
    }
    else {
        $Item = "$SoftwareName"
    }

    if ($Script:FailedSoftwareList -notcontains $Item) {
        $Script:FailedSoftwareList += $Item
    }

    Write-Log "记录安装失败：$Item" "ERROR"
}

function Enable-BuiltInAdministrator {
    param(
        [string]$PasswordPlainText
    )

    Write-Host ""
    Write-Host "开始配置内置 Administrator 账号" -ForegroundColor Yellow
    Write-Log "开始配置内置 Administrator 账号"

    try {
        # 通过 SID 结尾 -500 查找内置管理员账号，避免系统语言或重命名导致找不到
        $BuiltInAdmin = Get-LocalUser | Where-Object {
            $_.SID.Value -match "-500$"
        } | Select-Object -First 1

        if (-not $BuiltInAdmin) {
            throw "未找到内置 Administrator 账号（SID 结尾 -500）。"
        }

        Write-Host "检测到内置管理员账号：$($BuiltInAdmin.Name)" -ForegroundColor Yellow
        Write-Log "检测到内置管理员账号：$($BuiltInAdmin.Name)"

        $SecurePassword = ConvertTo-SecureString $PasswordPlainText -AsPlainText -Force

        # 设置密码
        Set-LocalUser -Name $BuiltInAdmin.Name -Password $SecurePassword -ErrorAction Stop

        # 设置密码永不过期
        Set-LocalUser -Name $BuiltInAdmin.Name -PasswordNeverExpires $true -ErrorAction Stop

        # 启用账号
        Enable-LocalUser -Name $BuiltInAdmin.Name -ErrorAction Stop

        Write-Host "内置 Administrator 账号已启用，密码已设置，密码永不过期。" -ForegroundColor Green
        Write-Log "内置 Administrator 账号已启用，密码已设置，密码永不过期。" "SUCCESS"

        return $true
    }
    catch {
        Write-Host "内置 Administrator 账号配置失败：$($_.Exception.Message)" -ForegroundColor Red
        Write-Log "内置 Administrator 账号配置失败：$($_.Exception.Message)" "ERROR"

        if (Get-Command Register-InstallFailure -ErrorAction SilentlyContinue) {
            Register-InstallFailure -SoftwareName "内置 Administrator 账号配置" -Reason $_.Exception.Message
        }

        return $false
    }
}

function Write-InstallResult {
    param(
        [string]$SoftwareName,
        [int]$ExitCode
    )

    if ($ExitCode -eq 0 -or $ExitCode -eq 3010) {
        Write-Host "$SoftwareName 安装成功，ExitCode=$ExitCode" -ForegroundColor Green
        Write-Log "$SoftwareName 安装成功，ExitCode=$ExitCode" "SUCCESS"
    }
    else {
        Write-Host "$SoftwareName 安装失败，ExitCode=$ExitCode" -ForegroundColor Red
        Write-Log "$SoftwareName 安装失败，ExitCode=$ExitCode" "ERROR"
        Register-InstallFailure -SoftwareName $SoftwareName -Reason "ExitCode=$ExitCode"
    }
}

function Complete-SetupAndReboot {
    param(
        [string]$EnvironmentName
    )

    if ($Script:InstallFailed) {
        Write-Host ""
        Write-Host "检测到有软件安装失败！" -ForegroundColor Red
        Write-Host "为避免丢失安装文件，脚本不会清理 C:\temp，也不会自动重启。" -ForegroundColor Red
        Write-Host ""
        Write-Host "失败的软件如下：" -ForegroundColor Red

        foreach ($FailedItem in $Script:FailedSoftwareList) {
            Write-Host " - $FailedItem" -ForegroundColor Red
        }

        Write-Host ""
        Write-Host "请操作员根据日志和提示手动处理失败项。" -ForegroundColor Yellow
        Write-Host "日志路径：$Script:LogFile" -ForegroundColor Yellow

        Write-Log "$EnvironmentName 流程检测到软件安装失败，跳过 C:\temp 清理和自动重启" "ERROR"
        foreach ($FailedItem in $Script:FailedSoftwareList) {
            Write-Log "失败项：$FailedItem" "ERROR"
        }

        Read-Host "按回车键退出"
        exit 1
    }

    Write-Host ""
    Write-Host "开始清理 C:\temp，保留 InstallLogs 日志文件夹" -ForegroundColor Yellow
    Write-Log "$EnvironmentName 流程执行完成，准备清理 C:\temp，保留 InstallLogs 日志文件夹"

    Get-ChildItem "C:\temp" -Force |
    Where-Object { $_.FullName -ine $Script:LogDir } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "C:\temp 清理完成，准备重启" -ForegroundColor Yellow
    Write-Log "C:\temp 清理完成，准备重启"

    shutdown.exe /r /t 120 /c "加域完成，2分钟后重启！"
}

#verify domain account
function Test-DomainCredential {
    param(
        [System.Management.Automation.PSCredential]$Credential,
        [string]$DomainName
    )

    try {
        $UserName = $Credential.UserName
        $Password = $Credential.GetNetworkCredential().Password

        $Entry = New-Object DirectoryServices.DirectoryEntry("LDAP://$DomainName", $UserName, $Password)

        # 触发认证
        $null = $Entry.NativeObject

        $Entry.Dispose()
        return $true
    }
    catch {
        return $false
    }
}

function Register-DeleteCurrentSetupUserTask {
    $TaskName = "DeleteTemporarySetupUser"
    $ScriptDir = "C:\ProgramData\HSPHARM"
    $ScriptPath = Join-Path $ScriptDir "DeleteTemporarySetupUser.ps1"

    New-Item -Path $ScriptDir -ItemType Directory -Force | Out-Null

    $CurrentUser = (Get-CimInstance Win32_ComputerSystem).UserName

    if (-not $CurrentUser) {
        Write-Host "未检测到当前登录用户，跳过临时账号删除任务。" -ForegroundColor Yellow
        Write-Log "未检测到当前登录用户，跳过临时账号删除任务。" "WARNING"
        return
    }

    $UserParts = $CurrentUser -split "\\", 2
    $UserDomain = $UserParts[0]
    $UserName = $UserParts[1]

    if ($UserDomain -ne $env:COMPUTERNAME) {
        Write-Host "当前登录用户不是本地账号：$CurrentUser，跳过删除。" -ForegroundColor Yellow
        Write-Log "当前登录用户不是本地账号：$CurrentUser，跳过删除。" "WARNING"
        return
    }

    $LocalUser = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue

    if (-not $LocalUser) {
        Write-Host "未找到本地账号：$UserName，跳过删除。" -ForegroundColor Yellow
        Write-Log "未找到本地账号：$UserName，跳过删除。" "WARNING"
        return
    }

    if ($LocalUser.SID.Value -match "-500$") {
        Write-Host "当前账号是内置 Administrator，禁止删除。" -ForegroundColor Red
        Write-Log "当前账号是内置 Administrator，禁止删除。" "ERROR"
        return
    }

    $ScriptContent = @"
Start-Sleep -Seconds 30

try {
    `$User = Get-LocalUser -Name "$UserName" -ErrorAction SilentlyContinue

    if (`$User -and `$User.SID.Value -notmatch "-500$") {
        Remove-LocalUser -Name "$UserName" -ErrorAction Stop
    }

    Unregister-ScheduledTask -TaskName "$TaskName" -Confirm:`$false -ErrorAction SilentlyContinue
    Remove-Item "$ScriptPath" -Force -ErrorAction SilentlyContinue
}
catch {
}
"@

    Set-Content -Path $ScriptPath -Value $ScriptContent -Encoding UTF8 -Force

    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""
    $Trigger = New-ScheduledTaskTrigger -AtStartup
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Force

    Write-Host "已创建临时账号删除任务，重启后会自动删除当前本地账号：$UserName。" -ForegroundColor Green
    Write-Log "已创建临时账号删除任务，重启后会自动删除当前本地账号：$UserName。" "SUCCESS"
}

function Install-Office2016AfterRemoveM365 {
    Write-Host ""
    Write-Host "开始检查是否存在预装 Microsoft 365 / Office 365"
    Write-Log "开始检查是否存在预装 Microsoft 365 / Office 365"

    $UninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $M365Apps = Get-ItemProperty $UninstallPaths -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -and
            (
                $_.DisplayName -match "Microsoft 365" -or
                $_.DisplayName -match "Office 365"
            ) -and
            $_.DisplayName -notmatch "Visio" -and
            $_.DisplayName -notmatch "Project" -and
            $_.DisplayName -notmatch "Language" -and
            $_.DisplayName -notmatch "Proofing"
        } |
        Select-Object DisplayName, DisplayVersion -Unique

    if ($M365Apps) {
        Write-Host "检测到预装 Microsoft 365 / Office 365：" -ForegroundColor Yellow
        Write-Log "检测到预装 Microsoft 365 / Office 365" "WARNING"

        foreach ($App in $M365Apps) {
            Write-Host ("已安装：" + $App.DisplayName + " " + $App.DisplayVersion) -ForegroundColor Yellow
            Write-Log ("已安装：" + $App.DisplayName + " " + $App.DisplayVersion) "WARNING"
        }

        $ODTDir = "C:\temp\ODT"
        $ODTSetup = Join-Path $ODTDir "setup.exe"
        $RemoveXml = Join-Path $ODTDir "remove_office_c2r.xml"

        if (-not (Test-Path $ODTSetup)) {
            Write-Host "未找到 ODT setup.exe，无法静默卸载 Microsoft 365：$ODTSetup" -ForegroundColor Red
            Write-Log "未找到 ODT setup.exe，无法静默卸载 Microsoft 365：$ODTSetup" "ERROR"
            Write-Host "为避免 Office 冲突，跳过 Office2016 安装。" -ForegroundColor Red
            Write-Log "为避免 Office 冲突，跳过 Office2016 安装。" "ERROR"
            Register-InstallFailure -SoftwareName "Office2016ProPlus" -Reason "检测到 Microsoft 365 但未找到 ODT setup.exe，未执行 Office2016 安装"
            return $false
        }

        $RemoveXmlContent = @"
<Configuration>
  <Remove All="TRUE" />
  <Display Level="None" AcceptEULA="TRUE" />
</Configuration>
"@

        Set-Content -Path $RemoveXml -Value $RemoveXmlContent -Encoding UTF8

        Write-Host "开始静默卸载 Microsoft 365 / Office 365" -ForegroundColor Yellow
        Write-Log "开始通过 ODT 静默卸载 Microsoft 365 / Office 365"

        $RemoveProcess = Start-Process -FilePath $ODTSetup `
            -ArgumentList "/configure `"$RemoveXml`"" `
            -Wait `
            -PassThru

        if ($RemoveProcess.ExitCode -eq 0 -or $RemoveProcess.ExitCode -eq 3010) {
            Write-Host "Microsoft 365 / Office 365 卸载完成，ExitCode=$($RemoveProcess.ExitCode)" -ForegroundColor Green
            Write-Log "Microsoft 365 / Office 365 卸载完成，ExitCode=$($RemoveProcess.ExitCode)" "SUCCESS"
            Start-Sleep -Seconds 20
        }
        else {
            Write-Host "Microsoft 365 / Office 365 卸载失败，ExitCode=$($RemoveProcess.ExitCode)" -ForegroundColor Red
            Write-Log "Microsoft 365 / Office 365 卸载失败，ExitCode=$($RemoveProcess.ExitCode)" "ERROR"
            Write-Host "为避免 Office 冲突，跳过 Office2016 安装。" -ForegroundColor Red
            Write-Log "为避免 Office 冲突，跳过 Office2016 安装。" "ERROR"
            Register-InstallFailure -SoftwareName "Microsoft 365 / Office 365 卸载" -Reason "ExitCode=$($RemoveProcess.ExitCode)"
            Register-InstallFailure -SoftwareName "Office2016ProPlus" -Reason "Microsoft 365 未卸载成功，跳过安装"
            return $false
        }
    }
    else {
        Write-Host "未检测到预装 Microsoft 365 / Office 365，直接安装 Office2016ProPlus" -ForegroundColor Green
        Write-Log "未检测到预装 Microsoft 365 / Office 365，直接安装 Office2016ProPlus" "SUCCESS"
    }

    $OfficeInstaller = "C:\temp\Office2016\setup.exe"

    if (-not (Test-Path $OfficeInstaller)) {
        Write-Host "Office2016 安装失败，未找到安装程序：$OfficeInstaller" -ForegroundColor Red
        Write-Log "Office2016 安装失败，未找到安装程序：$OfficeInstaller" "ERROR"
        Register-InstallFailure -SoftwareName "Office2016ProPlus" -Reason "未找到安装程序 $OfficeInstaller"
        return $false
    }

    Write-Host "开始安装 Office2016ProPlus"
    Write-Host ""
    Write-Log "开始安装 Office2016ProPlus"

    $OfficeProcess = Start-Process -FilePath $OfficeInstaller -Wait -PassThru
    Write-InstallResult -SoftwareName "Office2016ProPlus" -ExitCode $OfficeProcess.ExitCode

    if ($OfficeProcess.ExitCode -eq 0 -or $OfficeProcess.ExitCode -eq 3010) {
        return $true
    }
    else {
        return $false
    }
}


Write-Log "脚本开始执行，当前计算机名：$env:COMPUTERNAME"
$LocalAdminPassword = "hspharm@Gjdx2023"

$AdminConfigResult = Enable-BuiltInAdministrator -PasswordPlainText $LocalAdminPassword

if (-not $AdminConfigResult) {
    Write-Host "内置 Administrator 账号配置失败，脚本会继续执行，但最后不会自动清理和重启。" -ForegroundColor Red
    Write-Log "内置 Administrator 账号配置失败，继续后续流程。" "ERROR"
}
# Office 2016 安装：先检测并静默卸载预装 Microsoft 365 / Office 365，再安装 Office 2016


# Standard package install
function Install-StandardPackage {
    Write-Host ""
    Write-Host "开始安装办公软件"
    Write-Host ""
    Write-Log "开始安装标准办公软件包"

    #install office2016proplus
    $OfficeResult = Install-Office2016AfterRemoveM365
    if (-not $OfficeResult) {
        Write-Host "Office2016 未安装成功，继续安装后续办公软件。" -ForegroundColor Yellow
        Write-Log "Office2016 未安装成功，继续安装后续办公软件。" "WARNING"
    }
    Write-Host ""

    #install tencent meeting
    Write-Host "开始安装腾讯会议"
    Write-Host ""
    $TMProcess = Start-Process -FilePath "C:\temp\TencentMeeting.exe" -ArgumentList '/SilentInstall=0 /Language="zh-cn"' -Wait -PassThru
    Write-InstallResult -SoftwareName "腾讯会议" -ExitCode $TMProcess.ExitCode
    Write-Host ""

    Start-Sleep -Seconds 5

    #install tencent meeting outlook adds-on
    Write-Host "开始安装腾讯会议outlook插件"
    Write-Host ""
    $TMOutlook = Start-Process -FilePath "C:\temp\WeMeetOutlookPlugin.exe" -ArgumentList "/S" -Wait -PassThru
    Write-InstallResult -SoftwareName "腾讯会议Outlook插件" -ExitCode $TMOutlook.ExitCode
    Write-Host ""

    #install acrobat reader
    Write-Host "开始安装 PDF reader"
    Write-Host ""
    $PDFReader = Start-Process -FilePath "C:\temp\AcroRdrDC.exe" -ArgumentList "/sAll /rs /msi EULA_ACCEPT=YES" -Wait -PassThru
    Write-InstallResult -SoftwareName "Adobe Acrobat Reader" -ExitCode $PDFReader.ExitCode
    Write-Host ""

    #install 7zip
    Write-Host "开始安装7zip"
    Write-Host ""
    $ZipProcess = Start-Process -FilePath "C:\temp\7z2601-x64.exe" -ArgumentList "/S" -Wait -PassThru
    Write-InstallResult -SoftwareName "7-Zip" -ExitCode $ZipProcess.ExitCode
    Write-Host ""

    #install chrome
    Write-Host "开始安装chrome"
    Write-Host ""
    $msipath = "C:\temp\googlechromestandaloneenterprise64.msi"
    $chrome = Start-Process -FilePath msiexec -ArgumentList "/i `"$msipath`" /qn /norestart" -Wait -PassThru
    Write-InstallResult -SoftwareName "Google Chrome" -ExitCode $chrome.ExitCode
    Write-Host ""

    #install wechat work
    Write-Host "开始安装企业微信"
    Write-Host ""
    $WxWork = Start-Process -FilePath "C:\temp\WeCom.exe" -ArgumentList "/S" -Wait -PassThru
    Write-InstallResult -SoftwareName "企业微信" -ExitCode $WxWork.ExitCode
    Write-Host ""

    #Install VPN2
    Write-Host "开始安装Motion Pro"
    Write-Host ""
    $VPNpath = "C:\temp\MotionPro_Windows.msi"
    $VPN = Start-Process -FilePath msiexec -ArgumentList "/i `"$VPNpath`" /qn /norestart" -Wait -PassThru
    Write-InstallResult -SoftwareName "MotionPro" -ExitCode $VPN.ExitCode
    Write-Host ""

    Write-Log "标准办公软件包安装流程结束"
}

function Install-Encryption {
    Write-Host ""
    Write-Host "开始安装加密软件"
    Write-Log "开始安装加密软件"

    $encrypt = Start-Process -FilePath "C:\temp\亿赛通加密软件\V3.8S_Client\setup.exe" `
        -ArgumentList '/s /L0x0804 /f1"C:\temp\亿赛通加密软件\V3.8S_Client\CDG_setup.iss"' `
        -WorkingDirectory "C:\temp\亿赛通加密软件\V3.8S_Client" `
        -Wait `
        -PassThru

    Write-InstallResult -SoftwareName "亿赛通加密软件" -ExitCode $encrypt.ExitCode
}

#Install Mcafee 
function Install-AV1 {
    Write-Host ""
    Write-Host "开始安装杀毒软件"
    Write-Log "开始安装杀毒软件"

    $AVDir = "C:\temp\Mcafee"

    $AV = Start-Process -FilePath "$AVDir\McAfee.exe" -ArgumentList "/INSTALL=AGENT /SILENT /FORCEINSTALL" -Wait -PassThru
    Write-InstallResult -SoftwareName "McAfee Agent" -ExitCode $AV.ExitCode

    Start-Sleep -Seconds 30

    if ($AV.ExitCode -eq 0 -or $AV.ExitCode -eq 3010) {

        #Install Mcafee ENS
        Write-Host ""
        Write-Host "开始安装ENS"
        Write-Log "开始安装 ENS"

        $ENS = Start-Process -FilePath "$AVDir\ENS\setupEP.exe" -ArgumentList 'ADDLOCAL="tp" /quiet' -Wait -PassThru
        Write-InstallResult -SoftwareName "McAfee ENS" -ExitCode $ENS.ExitCode

        #Install FRP
        Write-Host ""
        Write-Host "开始安装FRP"
        Write-Log "开始安装 FRP"

        $FRPDIR = "$AVDir\FRP\MfeFRP_Client_5.5.0.267\eeff64.msi"
        $FRP = Start-Process -FilePath msiexec -ArgumentList "/i `"$FRPDIR`" /quiet /norestart REBOOT=ReallySuppress" -Wait -PassThru
        Write-InstallResult -SoftwareName "McAfee FRP" -ExitCode $FRP.ExitCode

        #Install Mcafee DLP
        Write-Host ""
        Write-Host "开始安装DLP模块"
        Write-Log "开始安装 DLP 模块"

        $DLP = Start-Process -FilePath "$AVDir\DLP\DLPAgentInstaller.x64.exe" -ArgumentList "/exenoui /quiet" -Wait -PassThru
        Write-InstallResult -SoftwareName "McAfee DLP" -ExitCode $DLP.ExitCode
    }
    else {
        Write-Host "McAfee Agent 安装失败，跳过 ENS、FRP、DLP 安装" -ForegroundColor Red
        Write-Log "McAfee Agent 安装失败，跳过 ENS、FRP、DLP 安装" "ERROR"
    }
}

#Install 联软
function Install-Lianruan {
    Write-Host ""
    Write-Host "开始安装联软"
    Write-Host ""
    Write-Log "开始安装联软"

    $InstallerPath     = "C:\temp\联软桌面助手.exe"
    $ServiceName       = "UniAccessAgent"
    $InitialWaitSec    = 60    # 先固定等待1分钟
    $TimeoutSec        = 600   # 后续最多再等10分钟
    $IntervalSec       = 5     # 每5秒检测一次

    if (-not (Test-Path $InstallerPath)) {
        Write-Host "联软安装失败，未找到安装程序：$InstallerPath" -ForegroundColor Red
        Write-Log "联软安装失败，未找到安装程序：$InstallerPath" "ERROR"
        Register-InstallFailure -SoftwareName "联软" -Reason "未找到安装程序 $InstallerPath"
        return $false
    }

    try {
        Start-Process -FilePath $InstallerPath -ArgumentList "/quiet /NoQueryBox"
        Write-Log "已启动联软安装程序"
    }
    catch {
        Write-Host "联软安装程序启动失败" -ForegroundColor Red
        Write-Log "联软安装程序启动失败：$($_.Exception.Message)" "ERROR"
        Register-InstallFailure -SoftwareName "联软" -Reason "安装程序启动失败：$($_.Exception.Message)"
        return $false
    }

    Write-Host "已启动联软安装，先等待 $InitialWaitSec 秒..."
    Start-Sleep -Seconds $InitialWaitSec

    Write-Host "开始检测联软服务 $ServiceName，每 $IntervalSec 秒检测一次，最多等待 $TimeoutSec 秒..."

    $Elapsed = 0

    while ($Elapsed -lt $TimeoutSec) {
        $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

        if ($Service) {
            Write-Host "联软安装成功，检测到服务 $ServiceName" -ForegroundColor Green
            Write-Log "联软安装成功，检测到服务 $ServiceName，当前状态：$($Service.Status)" "SUCCESS"
            return $true
        }

        Start-Sleep -Seconds $IntervalSec
        $Elapsed += $IntervalSec
    }

    Write-Host "联软安装失败，等待 $InitialWaitSec 秒后，又检测 $TimeoutSec 秒，仍未发现服务 $ServiceName" -ForegroundColor Red
    Write-Log "联软安装失败，等待 $InitialWaitSec 秒后，又检测 $TimeoutSec 秒，仍未发现服务 $ServiceName" "ERROR"
    Register-InstallFailure -SoftwareName "联软" -Reason "未检测到服务 $ServiceName"

    return $false
}

#Install 半透明mcafee
function Install-AV2 {
    Write-Host ""
    Write-Host "开始安装半透明mcafee"
    Write-Host ""
    Write-Log "开始安装半透明 McAfee"

    $AV2 = Start-Process -FilePath "C:\temp\EUAPackage_TA584_TP10.7.18.exe" -ArgumentList "-y" -PassThru -Wait
    Write-InstallResult -SoftwareName "半透明McAfee" -ExitCode $AV2.ExitCode
}

#Install 刷卡打印插件
function Install-Print {
    Write-Host ""
    Write-Host "开始安装刷卡打印插件"
    Write-Host ""
    Write-Log "开始安装刷卡打印插件"

    Start-Process -FilePath "C:\temp\PrintToCloud setup.exe" -ArgumentList "-silent 10.102.27.15 -force -mono"

    Start-Sleep -Seconds 120

    if (Test-Path "C:\rsprinterex\PrintToCloud.exe") {
        Write-Host "刷卡打印插件安装成功" -ForegroundColor Green
        Write-Log "刷卡打印插件安装成功，检测到 C:\rsprinterex\PrintToCloud.exe" "SUCCESS"
    }
    else {
        Write-Host "刷卡打印插件安装失败" -ForegroundColor Red
        Write-Log "刷卡打印插件安装失败，未检测到 C:\rsprinterex\PrintToCloud.exe" "ERROR"
        Register-InstallFailure -SoftwareName "刷卡打印插件" -Reason "未检测到 C:\rsprinterex\PrintToCloud.exe"
    }
}

#Install 企业网盘
function Install-NetDrive {
    Write-Host ""
    Write-Host "开始安装企业网盘"
    Write-Host ""
    Write-Log "开始安装企业网盘"

    Start-Process -FilePath "C:\temp\翰森制药企业网盘\zBox_installer.exe" -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-"

    Start-Sleep -Seconds 120

    if (Get-Process zbox_client -ErrorAction SilentlyContinue) {
        Write-Host "企业网盘安装成功" -ForegroundColor Green
        Write-Log "企业网盘安装成功，检测到进程 zbox_client" "SUCCESS"
    }
    else {
        Write-Host "企业网盘安装失败" -ForegroundColor Red
        Write-Log "企业网盘安装失败，未检测到进程 zbox_client" "ERROR"
        Register-InstallFailure -SoftwareName "企业网盘" -Reason "未检测到进程 zbox_client"
    }
}
#Domain binding and check
function Join-DomainWithCheck {
    param(
        [string]$ComputerName,
        [string]$DomainName,
        [System.Management.Automation.PSCredential]$Credential
    )

    try {
        Write-Host ""
        Write-Host "开始修改计算机名并加入域" -ForegroundColor Yellow
        Write-Log "准备修改计算机名为：$ComputerName"

        Rename-Computer -NewName $ComputerName -Force -ErrorAction Stop

        Write-Log "准备加入域：$DomainName"

        Add-Computer -DomainName $DomainName `
            -Options JoinWithNewName `
            -Force `
            -Credential $Credential `
            -ErrorAction Stop

        Write-Host "计算机改名和加域成功。" -ForegroundColor Green
        Write-Log "计算机改名和加域成功，新计算机名：$ComputerName，域：$DomainName" "SUCCESS"

        return $true
    }
    catch {
        Write-Host ""
        Write-Host "加域失败，但脚本会继续执行后续安装流程。" -ForegroundColor Red
        Write-Host "最后不会自动清理 C:\temp，也不会自动重启。" -ForegroundColor Yellow
        Write-Host "请检查域账号密码、网络、DNS、计算机名是否重复。" -ForegroundColor Yellow
        Write-Host "错误信息：$($_.Exception.Message)" -ForegroundColor Red

        Write-Log "加域失败，但继续后续流程：$($_.Exception.Message)" "ERROR"

        Register-InstallFailure -SoftwareName "改名加域" -Reason $_.Exception.Message

        return $false
    }
}

$DomainName = "hs.hspharm.com"

Write-Host "请输入计算机名" -ForegroundColor Yellow
$CN = Read-Host
Write-Log "输入的新计算机名：$CN"

do {
    Write-Host "请输入有加域权限的管理员账号" -ForegroundColor Yellow
    Write-Host "建议格式：HS\用户名 或 用户名@hs.hspharm.com" -ForegroundColor Yellow

    $Cred = Get-Credential

    Write-Host "正在验证账号密码..." -ForegroundColor Yellow
    Write-Log "开始验证域账号：$($Cred.UserName)"

    if (Test-DomainCredential -Credential $Cred -DomainName $DomainName) {
        Write-Host "账号密码验证通过" -ForegroundColor Green
        Write-Log "账号密码验证通过：$($Cred.UserName)" "SUCCESS"
        $CredValid = $true
    }
    else {
        Write-Host "账号密码验证失败，请重新输入。" -ForegroundColor Red
        Write-Log "账号密码验证失败：$($Cred.UserName)" "ERROR"
        $CredValid = $false
    }
}
until ($CredValid)

# Image select
do {
    Write-Host "请选择环境"
    Write-Host "1. 标准环境"
    Write-Host "2. 半透明环境"

    $Image = Read-Host

    switch ($Image) {
        "1" {
            $ImageEnv = "标准环境"
            $ImageCode = "standard"
            $validChoice = $true
        }
        "2" {
            $ImageEnv = "半透明环境"
            $ImageCode = "halfbypass"
            $validChoice = $true
        }
        default {
            Write-Host "输入无效，请重新选择1或2。" -ForegroundColor Red
            Write-Host ""
            $validChoice = $false
        }
    }
}
until ($validChoice)

Write-Host ""
Write-Host "执行'$ImageEnv'"
Write-Log "用户选择环境：$ImageEnv"

if ($ImageCode -eq "standard") {

    Write-Log "开始执行标准环境安装流程"

    Install-StandardPackage

    Start-Sleep -Seconds 20

    Install-Print

    Start-Sleep -Seconds 10

    Install-NetDrive

    Start-Sleep -Seconds 10

    Install-Encryption

    Start-Sleep -Seconds 20

    Install-AV1

    Start-Sleep -Seconds 10

    Join-DomainWithCheck -ComputerName $CN -DomainName $DomainName -Credential $Cred

    Install-Lianruan

    Start-Sleep -Seconds 10

    Register-DeleteCurrentSetupUserTask

    Start-sleep -Seconds 10

    Complete-SetupAndReboot -EnvironmentName "标准环境"
}
elseif ($ImageCode -eq "halfbypass") {

    Write-Log "开始执行半透明环境安装流程"

    Install-StandardPackage

    Start-Sleep -Seconds 20

    Install-Print

    Start-Sleep -Seconds 10

    Install-NetDrive

    Start-Sleep -Seconds 10

    Install-Encryption

    Start-Sleep -Seconds 20

    Install-AV2

    Start-Sleep -Seconds 10

    Join-DomainWithCheck -ComputerName $CN -DomainName $DomainName -Credential $Cred  

    Install-Lianruan

    Start-Sleep -Seconds 10

    Register-DeleteCurrentSetupUserTask

    Start-sleep -Seconds 10

    Complete-SetupAndReboot -EnvironmentName "半透明环境"
}
