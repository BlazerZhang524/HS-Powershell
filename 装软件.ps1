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
#Standard package install
Set-ExecutionPolicy RemoteSigned -Scope Process -Force
function Install-StandardPackage{
Write-Host ""
Write-Host "开始安装办公软件"
Write-Host ""
#install office2016proplus
Write-Host "安装Office2016ProPlus"
Write-Host ""
$OfficeProcess=Start-Process -FilePath "C:\temp\Office2016\setup.exe" -Wait -PassThru
if($OfficeProcess.ExitCode -eq 0 -or $OfficeProcess.ExitCode -eq 3010){Write-Host "Office2016安装成功" -ForegroundColor Green}
else{Write-Host "Office2016安装失败" -ForegroundColor Red}
Write-Host ""
#install tencent meeting
Write-Host "开始安装腾讯会议"
Write-Host ""
$TMProcess=Start-Process -FilePath "C:\temp\TencentMeeting.exe"  -ArgumentList '/SilentInstall=0 /Language="zh-cn"' -Wait -PassThru
if($TMProcess.ExitCode -eq 0 -or $TMProcess.ExitCode -eq 3010){Write-Host "腾讯会议安装成功" -ForegroundColor Green}
else{Write-Host "腾讯会议安装失败" -ForegroundColor Red}
Write-Host ""
Start-Sleep -Seconds 5
#install tencent meeting outlook adds-on
Write-Host "开始安装腾讯会议outlook插件"
Write-Host ""
$TMOutlook=Start-Process -FilePath "C:\temp\WeMeetOutlookPlugin.exe" -ArgumentList "/S" -Wait -PassThru
if($TMOutlook.ExitCode -eq 0 -or $TMOutlook.ExitCode -eq 3010){Write-Host "腾讯会议插件安装成功" -ForegroundColor Green}
else{Write-Host "腾讯会议插件安装失败" -ForegroundColor Red}
Write-Host ""
#install acrobat reader
Write-Host "开始安装 PDF reader"
Write-Host ""
$PDFReader=Start-Process -FilePath "c:\temp\AcroRdrDC.exe" -ArgumentList "/sAll /rs /msi EULA_ACCEPT=YES" -Wait -PassThru
if($PDFReader.ExitCode -eq 0 -or $PDFReader.ExitCode -eq 3010){Write-Host "PDF Reader 安装成功" -ForegroundColor Green}
else{Write-Host "PDF Reader 安装失败" -ForegroundColor Red}
Write-Host ""
#install 7zip
Write-Host "开始安装7zip"
Write-Host ""
$7zip=Start-Process -FilePath "c:\temp\7z2601-x64.exe" -ArgumentList "/S" -Wait -PassThru
if($7zip.ExitCode -eq 0 -or $7zip.ExitCode -eq 3010){Write-Host "7zip 安装成功" -ForegroundColor Green}
else{Write-Host "7zip安装失败" -ForegroundColor Red}
Write-Host ""
#install chrome
Write-Host "开始安装chrome"
Write-Host ""
$msipath="c:\temp\googlechromestandaloneenterprise64.msi"
$chrome=Start-Process -FilePath msiexec -ArgumentList "/i $msipath /qn /norestart" -Wait -PassThru
if($chrome.ExitCode -eq 0 -or $chrome.ExitCode -eq 3010){Write-Host "Chrome安装成功" -ForegroundColor Green}
else{Write-Host "Chrome 安装失败" -ForegroundColor Red}
Write-Host ""
#install wechat work
Write-Host "开始安装企业微信"
Write-Host ""
$WxWork=Start-Process -FilePath "c:\temp\WeCom.exe" -ArgumentList "/S" -Wait -PassThru
if($WxWork.ExitCode -eq 0 -or $WxWork.ExitCode -eq 3010){Write-Host "企业微信安装成功" -ForegroundColor Green}
else{Write-Host "企业微信安装失败" -ForegroundColor Red}
Write-Host ""
#Write-Host "开始安装VPN客户端"
Write-Host ""
#Install VPN1
#$VPNlocation="D:\laptop_setup\MotionPro"
#$VPNinstaller="$VPNlocation\MotionProSetup.exe"
#$VPNinstallfile="C:\Program Files\Array Networks\MotionPro VPN Client\MotionPro.exe"
#Push-Location $VPNlocation
#$VPN=Start-Process -FilePath $VPNinstaller -ArgumentList "/S /NCRC" 
#Start-Sleep -Seconds 120
#Pop-Location
#if(Test-Path $VPNinstallfile){Write-Host "VPN安装成功" -ForegroundColor Green}
#else{Write-Host "VPN安装失败" -ForegroundColor Red}
#Install VPN2
Write-Host "开始安装Motion Pro"
$VPNpath="c:\temp\MotionPro_Windows.msi"
$VPN=Start-Process -FilePath msiexec -ArgumentList "/i $VPNpath /qn /norestart" -Wait -PassThru
if($VPN.ExitCode -eq 0 -or $VPN.ExitCode -eq 3010){Write-Host "MotionPro 安装完成" -ForegroundColor Green}
else{Write-Host "MotionPro 安装失败"-ForegroundColor Red}
}
function Install-Encryption{
Write-Host ""
Write-Host "开始安装加密软件"
$encrypt=Start-Process -FilePath "c:\temp\亿赛通加密软件\V3.8S_Client\setup.exe" -ArgumentList '/s /L0x0804 /f1"c:\temp\亿赛通加密软件\V3.8S_Client\CDG_setup.iss"' -WorkingDirectory "D:\laptop_setup\亿赛通加密软件\V3.8S_Client" -Wait -PassThru
if($encrypt.ExitCode -eq 0 -or $encrypt.ExitCode -eq 3010){Write-Host "加密软件安装成功"}
else{Write-Host "加密软件安装失败"}
}
#Install Mcafee 
function Install-AV1{
Write-Host ""
Write-Host "开始安装杀毒软件"
$AVDir="c:\temp\Mcafee"
$AV=Start-Process -FilePath "$AVDir\McAfee.exe" -ArgumentList "/INSTALL=AGENT /SILENT /FORCEINSTALL" -Wait -PassThru
Start-Sleep -Seconds 30
if($AV.ExitCode -eq 0 -or $AV.ExitCode -eq 3010)
{
Write-Host "杀毒软件主程序安装成功。"
Write-Host ""
#Install Mcafee ENS
Write-Host "开始安装ENS"
$ENS=Start-Process -FilePath "$AVDir\ENS\setupEP.exe" -ArgumentList 'ADDLOCAL="tp" /quiet' -Wait -PassThru
if($ENS.ExitCode -eq 0){Write-Host "ENS 安装成功"}
else{Write-Host "ENS 安装失败"}
Write-Host ""
#Install FRP
Write-Host "开始安装FRP"
$FRPDIR="$AVDir\FRP\MfeFRP_Client_5.5.0.267\eeff64.msi" 
$FRP=Start-Process -FilePath msiexec -ArgumentList "/i $FRPDIR /quiet /norestart REBOOT=ReallySuppress" -wait -passthru
if($FRP.ExitCode -eq 0 -or $FRP.ExitCode -eq 3010){Write-Host "FRP安装成功"}
else{Write-Host "FRP安装失败"}
#Install Mcafee DLP
Write-Host "开始安装DLP模块"
$DLP=Start-Process -FilePath "$AVDir\DLP\DLPAgentInstaller.x64.exe" -ArgumentList "/exenoui /quiet" -Wait -PassThru
if($DLP.ExitCode -eq 0){Write-Host "DLP 安装成功"}
}
}
#Install 联软
function Install-Lianruan{
Write-Host ""
Write-Host "开始安装联软"
Write-Host ""
$Lianruan=Start-Process -FilePath "c:\temp\联软桌面助手.exe" -ArgumentList "/quiet /NoQueryBox" 
Start-Sleep 120
if(Get-Service UniAccessAgent -ErrorAction SilentlyContinue){Write-Host "联软安装成功" -ForegroundColor Green}
else{Write-Host "联软安装失败" -ForegroundColor Red}
}

#Set computer name

Write-Host "请输入计算机名" -ForegroundColor Yellow
$CN=Read-Host
Write-Host "请输入管理员账号" -ForegroundColor Yellow
$Cred=Get-Credential
$DomainName= "hs.hspharm.com"

# Image select
do{
Write-Host "请选择环境"
Write-Host "1. 标准环境"
Write-Host "2. 半透明环境"

$Image=Read-Host
switch($Image){
"1"{$ImageEnv="标准环境"
    $ImageCode='standard'
    $validChoice=$true}
"2"{$ImageEnv="半透明环境"
    $ImageCode="halfbypass"
    $validChoice=$true}
default{Write-Host "输入无效，请重新选择1或2。"-ForegroundColor Red
Write-Host ""
$validChoice = $false}
}

}
until ($validChoice)

Write-Host ""
Write-Host "执行'$ImageEnv'"

if($ImageCode -eq 'standard')
{
Install-StandardPackage
Start-Sleep -Seconds 20
Install-Encryption
Start-Sleep -Seconds 20
Install-AV1
Start-Sleep -Seconds 10
Rename-Computer -NewName $CN -Force
Add-Computer -DomainName $DomainName -Options JoinWithNewName -Force -Credential $Cred
shutdown.exe /r /t 120 /c "加域完成，2分钟后重启！"
}
elseif($ImageCode -eq 'halfbypass')
{
Install-StandardPackage
Start-Sleep -Seconds 10
Rename-Computer -NewName $CN -Force
Add-Computer -DomainName $DomainName -Options JoinWithNewName -Force -Credential $Cred
shutdown.exe /r /t 120 /c "加域完成，2分钟后重启！"
}
