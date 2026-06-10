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

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "$Time [$Level] $Message"

    Add-Content -Path $Script:LogFile -Value $Line -Encoding UTF8
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
    }
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

Write-Log "脚本开始执行，当前计算机名：$env:COMPUTERNAME"
# Standard package install
function Install-StandardPackage {
    Write-Host ""
    Write-Host "开始安装办公软件"
    Write-Host ""
    Write-Log "开始安装标准办公软件包"

    #install office2016proplus
    Write-Host "安装Office2016ProPlus"
    Write-Host ""
    $OfficeProcess = Start-Process -FilePath "C:\temp\Office2016\setup.exe" -Wait -PassThru
    Write-InstallResult -SoftwareName "Office2016ProPlus" -ExitCode $OfficeProcess.ExitCode
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

    Start-Process -FilePath "C:\temp\联软桌面助手.exe" -ArgumentList "/quiet /NoQueryBox"

    Start-Sleep 120

    if (Get-Service UniAccessAgent -ErrorAction SilentlyContinue) {
        Write-Host "联软安装成功" -ForegroundColor Green
        Write-Log "联软安装成功，检测到服务 UniAccessAgent" "SUCCESS"
    }
    else {
        Write-Host "联软安装失败" -ForegroundColor Red
        Write-Log "联软安装失败，未检测到服务 UniAccessAgent" "ERROR"
    }
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

        Write-Host "计算机改名和加域成功，准备继续清理并重启。" -ForegroundColor Green
        Write-Log "计算机改名和加域成功，新计算机名：$ComputerName，域：$DomainName" "SUCCESS"
    }
    catch {
        Write-Host ""
        Write-Host "加域失败，脚本已停止！" -ForegroundColor Red
        Write-Host "请检查域账号密码、网络、DNS、计算机名是否重复。" -ForegroundColor Red
        Write-Host "错误信息：$($_.Exception.Message)" -ForegroundColor Red

        Write-Log "加域失败，脚本停止：$($_.Exception.Message)" "ERROR"

        Read-Host "按回车键退出"
        exit 1
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

    Write-Host ""
    Write-Host "开始清理 C:\temp，保留 InstallLogs 日志文件夹" -ForegroundColor Yellow
    Write-Log "标准环境流程执行完成，准备清理 C:\temp，保留 InstallLogs 日志文件夹"

    Get-ChildItem "C:\temp" -Force |
    Where-Object { $_.FullName -ine $Script:LogDir } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "C:\temp 清理完成，准备重启" -ForegroundColor Yellow
    Write-Log "C:\temp 清理完成，准备重启"

    shutdown.exe /r /t 120 /c "加域完成，2分钟后重启！"
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

    Write-Host ""
    Write-Host "开始清理 C:\temp，保留 InstallLogs 日志文件夹" -ForegroundColor Yellow
    Write-Log "半透明环境流程执行完成，准备清理 C:\temp，保留 InstallLogs 日志文件夹"

    Get-ChildItem "C:\temp" -Force |
    Where-Object { $_.FullName -ine $Script:LogDir } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "C:\temp 清理完成，准备重启" -ForegroundColor Yellow
    Write-Log "C:\temp 清理完成，准备重启"

    shutdown.exe /r /t 120 /c "加域完成，2分钟后重启！"
}
