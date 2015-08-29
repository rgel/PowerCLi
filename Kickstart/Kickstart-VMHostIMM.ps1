#requires -version 3.0
#requires -Modules 'DnsServer'
#requires –PSSnapin 'VMware.VimAutomation.Core'

<#
.SYNOPSIS
    Deploy New VMHost with Kickstart ESXi ISO.
.DESCRIPTION
    Deploy New VMHost with Kickstart ESXi ISO
	on IBM/Lenovo server via IMM.
.PARAMETER IMMIPv4
    IBM server's IMM card IPv4 address.
.PARAMETER IMMHostname
    IBM server's IMM card Hostname.
.PARAMETER VMHostBorn
    New VMHost Hostname.
.PARAMETER KickstartISO
    ESXi Kickstart prepared ISO image.
.PARAMETER MgmtIPv4
	Management VMKernel Port IPv4 address.
.PARAMETER vMotionIPv4
	vMotion VMKernel Port IPv4 address.
.PARAMETER Env
	Virtual Environment - intended to support multiple Kickstart configurations.
	See #region Variables for example.
.PARAMETER CheckBusyIP
	Try to determine is Management and vMotion IP addresses
	are busy on the network by sending echo request.
.PARAMETER SaveBootOrder
	Save and restore original server's Boot Order after ESXi host deployment.
.PARAMETER Cred
	Rewrite VI Store Credentials.
.EXAMPLE
	C:\PS> .\Kickstart-VMHostIMM.ps1 -IMMIP "10.1.99.120" -VMHostBorn esxdmz08 -ISO '\\cifs\share\ESXi-5.5.0-1331820-IBM-20131115.iso' -MgmtIPv4 "192.168.203.16" -Env DMZ -CheckBusyIP:$false -SaveBootOrder
	Deploy ESXi host in DMZ environment without vMotion and save original server's Boot Order.
.EXAMPLE
	C:\PS> .\Kickstart-VMHostIMM.ps1 -IMM esxprd11r -ESXi esxprd11 -MgmtIP "10.200.21.111" -vMotionIP "10.200.22.111"
	Deploy ESXi host in default environment (NET), use default ISO image.
.EXAMPLE
	C:\PS> .\Kickstart-VMHostIMM.ps1 -Cred
	Rewrite existing credentials in VI Credential Store.
.NOTES
	Author: Roman Gelman.
.LINK
	http://goo.gl/XD9RpA
#>

#region Parameters

[CmdletBinding(DefaultParameterSetName='DNS')]

Param (

	[Parameter(Mandatory=$true,HelpMessage="IMM IPv4 Address",ParameterSetName='IP')]
		[Alias("IMMIP")]
	[System.Net.IPAddress]$IMMIPv4
	,
	[Parameter(Mandatory=$true,HelpMessage="IMM Hostname",ParameterSetName='DNS')]
		[ValidatePattern('^[A-Za-z\d_-]{1,15}$')]
		[Alias("IMM")]
	[System.String]$IMMHostname
	,
	[Parameter(Mandatory=$true,HelpMessage="Deployed VMHost Hostname",ParameterSetName='DNS')]
	[Parameter(Mandatory=$true,HelpMessage="Deployed VMHost Hostname",ParameterSetName='IP')]
		[ValidateNotNullorEmpty()]
		[Alias("ESXi")]
	[System.String]$VMHostBorn
	,
	[Parameter(Mandatory=$false,HelpMessage="Kickstart prepared ESXi installation ISO file",ParameterSetName='IP')]
	[Parameter(Mandatory=$false,HelpMessage="Kickstart prepared ESXi installation ISO file",ParameterSetName='DNS')]
		[ValidatePattern('^\.iso$')]
		[ValidateScript({Test-Path -Path FileSystem::$_ -PathType Leaf})]
		[Alias("ISO")]
	[System.String]$KickstartISO = '\\SRV6\inst$\VMWare\5.5\Lenovo-ESXi55U2.iso'
	,
	[Parameter(Mandatory=$true,HelpMessage="Management VMKernel Port IPv4 address",ParameterSetName='IP')]
	[Parameter(Mandatory=$true,HelpMessage="Management VMKernel Port IPv4 address",ParameterSetName='DNS')]
		[Alias ("MgmtIP")]
	[System.Net.IPAddress]$MgmtIPv4
	,
	[Parameter(Mandatory=$false,HelpMessage="vMotion VMKernel Port IPv4 address",ParameterSetName='IP')]
	[Parameter(Mandatory=$false,HelpMessage="vMotion VMKernel Port IPv4 address",ParameterSetName='DNS')]
		[Alias ("vMotionIP")]
	[System.Net.IPAddress]$vMotionIPv4
	,
	[Parameter(Mandatory=$false,HelpMessage="Virtual Environment",ParameterSetName='IP')]
	[Parameter(Mandatory=$false,HelpMessage="Virtual Environment",ParameterSetName='DNS')]
		[ValidateSet('NET','DMZ','CLOUD')]
		[Alias ("Environment")]
	[System.String]$Env = 'NET'
	,
	[Parameter(Mandatory=$false,HelpMessage="Try to ping Management and vMotion IP addresses",ParameterSetName='IP')]
	[Parameter(Mandatory=$false,HelpMessage="Try to ping Management and vMotion IP addresses",ParameterSetName='DNS')]
		[Alias ("CheckIP")]
	[System.Boolean]$CheckBusyIP = $true
	,
	[Parameter(Mandatory=$false,HelpMessage="Save and restore original server's Boot Order",ParameterSetName='IP')]
	[Parameter(Mandatory=$false,HelpMessage="Save and restore original server's Boot Order",ParameterSetName='DNS')]
	[Switch]$SaveBootOrder = $false
	,
	[Parameter(Mandatory=$false,HelpMessage="Rewrite VI Store Credentials",ParameterSetName='VIStoreCred')]
	[Switch]$Cred
	
)

#endregion Parameters

#region Variables

$scriptPath  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$asuExec     = $scriptPath + "\ASU\asu64.exe"
$rdMount     = $scriptPath + "\ASU\rdmount.exe"
$rdUMount    = $scriptPath + "\ASU\rdumount.exe"
$dnsCheck    = $null
$loginUser   = 'USERID'

Switch -exact ($Env) {

	'NET' {
	
		$ksCfgVMHost   = 'esxprdxx'
		$ksCfgRoot     = 'root'
		$ksCfgMgmtIP   = '10.200.21.160'
		$ksCfgMgmtMask = '255.255.255.0'
		$ksCfgvMoIP    = '10.200.22.160'
		$ksCfgvMoMask  = '255.255.255.0'
		$envDNSServer  = 'SRVDC1'
		$envDNSZone    = 'prd.iec.co.il'
		$envBehindFW   = $false
		Break
	}
	
	'DMZ' {
	
		$ksCfgVMHost   = 'esxdmzxx'
		$ksCfgRoot     = 'root'
		$ksCfgMgmtIP   = '192.168.203.15'
		$ksCfgMgmtMask = '255.255.255.240'
		$ksCfgvMoIP    = ''
		$envDNSServer  = 'SRVDNS02'
		$envDNSZone    = 'dmz.iec.co.il'
		$envBehindFW   = $true
		Break
	}
	
	'CLOUD' {

		Break
	}
}

If ($IMMIPv4 -eq '') {$IMM = $IMMHostname} Else {[string]$IMM = $IMMIPv4.IPAddressToString}
[string]$MgmtIPv4    = $MgmtIPv4.IPAddressToString
[string]$vMotionIPv4 = $vMotionIPv4.IPAddressToString

#endregion Variables

#region Prerequisites

$title = $Host.UI.RawUI.WindowTitle
$Host.UI.RawUI.WindowTitle = $MyInvocation.MyCommand.Name

###
### Rewrite VI credentials store for New deployed VMHost
###

If ($Cred) {
Write-Host "`nRewriting VI Credential Store item '$ksCfgVMHost-$ksCfgRoot' ..." -ForegroundColor Yellow

$xxCred = $viCred = $null
$xxUser = $xxPwd  = ''

Do {$xxCred = Get-Credential -UserName $ksCfgRoot -Message "New VMHost $ksCfgRoot"} While (!$xxCred)

If ($xxCred.Password.Length -lt 1) {
	Write-Host "Zero length root password is not allowed`n" -ForegroundColor DarkRed; Exit 1
} Else {
	$xxPwd  = $xxCred.GetNetworkCredential().Password
	$viCred = New-VICredentialStoreItem -Host $ksCfgVMHost -User $ksCfgRoot -Password $xxPwd
	If ($viCred) {Write-Host "VI Credentials Store item for '$ksCfgVMHost' VMHost successfully created`n" -ForegroundColor Green}
	Else {Write-Host "Failed to create VI Credentials Store item for '$ksCfgVMHost' VMHost`n" -ForegroundColor DarkRed; Exit 1}
}

Exit 0
}

###
### Additional executables & ISO
###

If (!(Test-Path -Path FileSystem::$KickstartISO -PathType Leaf)) {Write-Host "Kickstart ISO file '$KickstartISO' not found" -ForegroundColor DarkRed; Exit 1}
If (!(Test-Path -Path FileSystem::$asuExec -PathType Leaf))      {Write-Host "IBM ASU executable '$asuExec' not found" -ForegroundColor DarkRed; Exit 1}
If (!(Test-Path -Path FileSystem::$rdMount -PathType Leaf))      {Write-Host "IBM Remote Disk CLI executable '$rdMount' not found" -ForegroundColor DarkRed; Exit 1}
If (!(Test-Path -Path FileSystem::$rdUMount -PathType Leaf))     {Write-Host "IBM Remote Disk CLI executable '$rdUMount' not found" -ForegroundColor DarkRed; Exit 1}

###
### DNS server check
###

If (!$envBehindFW) {
	$dnsCheck = Get-DnsServerZone -Name $envDNSZone -ComputerName $envDNSServer -ErrorAction SilentlyContinue
	If (!$dnsCheck) {Write-Host "Failed validate zone '$envDNSZone' on DNS server '$envDNSServer'" -ForegroundColor DarkRed; Exit 1}
}

###
### Check VI credentials store for New deployed VMHost credentials
###

Write-Host "`nChecking VI Credential Store for '$ksCfgVMHost-$ksCfgRoot' credentials pair ..." -ForegroundColor Yellow
$viCred = $null
$viCred = Get-VICredentialStoreItem -Host $ksCfgVMHost -User $ksCfgRoot -ErrorAction SilentlyContinue
If (!$viCred) {
	Write-Host "'$ksCfgVMHost-$ksCfgRoot' credentials pair not found, please supply" -ForegroundColor Yellow
	
	$xxCred = $null
	$xxUser = $xxPwd = ''

	Do {$xxCred = Get-Credential -UserName $ksCfgRoot -Message "New VMHost $ksCfgRoot"} While (!$xxCred)

	If ($xxCred.Password.Length -lt 1) {
		Write-Host "Zero length root password is not allowed`n" -ForegroundColor DarkRed; Exit 1
	} Else {
		$xxPwd  = $xxCred.GetNetworkCredential().Password
		$viCred = New-VICredentialStoreItem -Host $ksCfgVMHost -User $ksCfgRoot -Password $xxPwd
		If ($viCred) {Write-Host "VI Credentials Store item for '$ksCfgVMHost' VMHost successfully created" -ForegroundColor Green}
		Else {Write-Host "Failed to create VI Credentials Store item for '$ksCfgVMHost' VMHost" -ForegroundColor DarkRed; Exit 1}
	}
} Else {
	Write-Host "Credentials pair '$ksCfgVMHost-$ksCfgRoot' already exists" -ForegroundColor Green
	Write-Host "To overwrite it, run this script with [-Cred] parameter"
}

###
### Check reply from initial IPv4 address of deployed VMHost (except environments that located behind firewalls)
###

If (!$envBehindFW) {

	If (Test-Connection -ComputerName $ksCfgMgmtIP -Count 1 -Quiet) {
		Write-Host "Initial IP address '$ksCfgMgmtIP' is busy on the network, deployment canceled`n" -ForegroundColor DarkRed
		Exit 1
	}
}

###
### Check reply from Mgmt IPv4 address of deployed VMHost
###

If ($CheckBusyIP -and (!$envBehindFW)) {

	Write-Host "`nChecking Management IP ..." -ForegroundColor Yellow

	If (Test-Connection -ComputerName $MgmtIPv4 -Count 1 -Quiet) {
		Write-Host "IP address '$MgmtIPv4' is busy on the network, deployment canceled`n" -ForegroundColor DarkRed
		Exit 1
	} Else {
		Write-Host "IP address '$MgmtIPv4' is not in use on the network" -ForegroundColor Green
	}
}

###
### Check reply from vMotion IPv4 address of deployed VMHost
###

If ($vMotionIPv4 -ne '' -and $CheckBusyIP -and (!$envBehindFW)) {

	Write-Host "`nChecking vMotion IP ..." -ForegroundColor Yellow

	If (Test-Connection -ComputerName $vMotionIPv4 -Count 1 -Quiet) {
		Write-Host "IP address '$vMotionIPv4' is busy on the network, deployment canceled`n" -ForegroundColor DarkRed
		Exit 1
	} Else {
		Write-Host "IP address '$vMotionIPv4' is not in use on the network" -ForegroundColor Green
	}
}

###
### Check DNS A-record, Exit only if A-record exists but not have the same IP address
###

If (!$envBehindFW) {
	Write-Host "`nChecking '$VMHostBorn' DNS A-record ..." -ForegroundColor Yellow
	$dnsRecordA = $null
	$dnsRecordA = Get-DnsServerResourceRecord -ComputerName $envDNSServer `
	-ZoneName $envDNSZone -Name $VMHostBorn -RRType "A"
	If ($dnsRecordA) {
		If ($MgmtIPv4 -eq $dnsRecordA.RecordData.IPv4Address.IPAddressToString) {
			Write-Host "DNS A-record exists and match to IP address '$MgmtIPv4'" -ForegroundColor Green
		} Else {
			Write-Host "DNS A-record exists but not match: VMHost:'$MgmtIPv4' | DNS:'$($dnsRecordA.RecordData.IPv4Address.IPAddressToString)'`n" `
			-ForegroundColor DarkRed
			Exit 1
		}
	} Else {
		Write-Host "DNS A-record for '$VMHostBorn' doesn't exists" -ForegroundColor Yellow
	}
}

###
### Get IMM credentials
###

$IMMCred    = $null
$IMMLoginID = $IMMPwd = ''

Do {$IMMCred = Get-Credential -UserName $loginUser -Message "IMM Supervisor LoginID"} While (!$IMMCred)

If ($IMMCred.Password.Length -lt 1) {
	Write-Host "Zero length password is prohibited`n" -ForegroundColor DarkRed; Exit 1
} Else {
	$IMMLoginID = $IMMCred.GetNetworkCredential().Username
	$IMMPwd     = $IMMCred.GetNetworkCredential().Password
}

$IMMBinding = " --host $IMM --user $IMMLoginID --password $IMMPwd"
$rdBinding  = " -s $IMM -l $IMMLoginID -p $IMMPwd"

###
### Save original Boot Order ###
###

If ($SaveBootOrder) {

	$origBO    = $strOrigBO = ''
	$arrOrigBO = @()

	Write-Host "`nConnecting to IMM '$IMM' ..." -ForegroundColor Yellow
	$asuCmdLine = $asuExec + " show BootOrder.BootOrder" + $IMMBinding
	$asuOUT = ''; $asuOUT = Invoke-Expression -Command $asuCmdLine
	$asuCutOut = [regex]::match($asuOUT, 'BootOrder.BootOrder=.+')

	If ($asuCutOut.Success) {
		Write-Host "Successfully connected to IMM '$IMM'`n" -ForegroundColor Green
		$origBO = $asuCutOut.Value.TrimStart('BootOrder.BootOrder=')
		$arrOrigBO = $origBO -split ('=')
		Foreach ($bootDevice in $arrOrigBO) {$strOrigBO += "`"" + $bootDevice + "`"="}
		$strOrigBO = $strOrigBO.TrimEnd('=')
		Write-Host "Original Boot Order is: $strOrigBO" -ForegroundColor Yellow
	} Else {
		Write-Host "Failed to save the Original Boot Order`n" -ForegroundColor DarkRed
		Exit 1
	}
}

###
### Change Boot Order: 'CD/DVD Rom' first
###

$cdFirstBO = '"CD/DVD Rom"="Floppy Disk"="Hard Disk 0"="PXE Network"'
$myBO = 'set BootOrder.BootOrder ' + $cdFirstBO + $IMMBinding
Write-Host "Changing Boot Order to: $cdFirstBO ..." -ForegroundColor Yellow
$asuProc = $null; $asuProc = Start-Process $asuExec -ArgumentList $myBO -Wait:$true -PassThru
If ($asuProc.ExitCode -eq 0) {
	Write-Host "Boot Order successfully changed" -ForegroundColor Green
} Else {
	Write-Host "Failed to change Boot Order`n" -ForegroundColor DarkRed
	Exit 1
}

$Host.UI.RawUI.WindowTitle = "Deploy VMHost '$VMHostBorn' ..."

#endregion Prerequisites

#region Mount Kickstart ISO image with IBM Remote Disk CLI

###
### Unmount any virtual media from IMM if exists
###

Write-Host "`nChecking IMM Virtual Media drive ..." -ForegroundColor Yellow
$rdArgsUmount = "-s " + "$IMM"
$rdProc = $null; $rdProc = Start-Process $rdUMount -ArgumentList $rdArgsUmount -PassThru -Wait:$true

###
### Check if successfully unmounted
###

If ($rdProc) {
	Switch ($rdProc.ExitCode) {
		-1		{Write-Host "Some Virtual Media unmounted" -ForegroundColor Green;  Break}
		32		{Write-Host "Virtual Media drive is empty" -ForegroundColor Green;  Break}
		Default	{Write-Host "Unknown Virtual Media status" -ForegroundColor Yellow; Break}
	}
}

###
### Mount ISO
###

Write-Host "`nMounting Kickstart ISO to IMM Virtual Media ..." -ForegroundColor Yellow
$rdArgsMount = "$rdBinding" + " -d " + "$KickstartISO"
Start-Process $rdMount -ArgumentList $rdArgsMount -Wait:$false -PassThru |Out-Null
Start-Sleep -Seconds 20

###
### Check if successfully mounted
###

$rdCmdLine = "$rdMount" + "$rdBinding" + " -q"
$rdOUT = ''; $rdOUT = Invoke-Expression -Command $rdCmdLine
$rdCutOut = [regex]::match($rdOUT, 'Token\s\d+\smounted')

If ($rdCutOut.Success) {
	Write-Host "Kickstart ISO file successfully mounted to IMM" -ForegroundColor Green
} Else {
	Write-Host "Failed to mount Kickstart ISO" -ForegroundColor DarkRed
	Exit 1
}

#endregion Mount Kickstart ISO image with IBM Remote Disk CLI

#region Reboot IBM server via IMM

Write-Host "`nRebooting IBM server ..." -ForegroundColor Yellow
$asuCmdLine = $asuExec + " immapp Rebootos" + $IMMBinding
$asuOUT = ''; $asuOUT = Invoke-Expression -Command $asuCmdLine
If ($asuOUT -like '*Issuing system reboot command*') {
	Write-Host "Server rebooted successfully" -ForegroundColor Green
} Else {
	Write-Host "Failed to reboot the server" -ForegroundColor DarkRed
	Exit 1
}

#endregion Reboot IBM server via IMM

#region Waiting for New VMHost to boot 1-st time

Write-Host "`nWaiting for New VMHost to boot first time [~30 min] ..." -ForegroundColor Yellow
$pingCmdLine = "ping -n 1 $ksCfgMgmtIP"
$i = 0
Do
{	
	$i += 1
	
	#region Revert Original Boot Order
	
	If ($SaveBootOrder -and $i -eq 15) {

		Write-Host "`nReverting to Original Boot Order ..." -ForegroundColor Yellow
		$rootBO = 'set BootOrder.BootOrder ' + $strOrigBO + $IMMBinding
		$asuProc = $null; $asuProc = Start-Process $asuExec -ArgumentList $rootBO -Wait:$true -PassThru
		If ($asuProc.ExitCode -eq 0) {
			Write-Host "Reverted successfully to: $strOrigBO`n" -ForegroundColor Green
		} Else {
			Write-Host "Sorry! Failed to revert to the Original Boot Order, please reconfigure manually`n" -ForegroundColor DarkRed
		}
	}
	
	#endregion Revert Original Boot Order
	
	$pingOUT = ''; $pingOUT = Invoke-Expression -Command $pingCmdLine
	If ($pingOUT -like '*Reply from*') {
		Write-Host "First phase of VMHost deployment finished, server booted" -ForegroundColor Green
	} Else {
		Write-Progress -Activity "VMHost Deployment" -Status "[$i] Deployment is in progress ..." `
		-PercentComplete ($i / 30 * 100 -as [int])
	}
	Start-Sleep -Seconds 60
}	While ($pingOUT -like '*Request timed out*')

#endregion Waiting for New VMHost to boot 1-st time

#region Waiting for New VMHost to reboot 2-nd time

Write-Host "`nWaiting for New VMHost to reboot second time ..." -ForegroundColor Yellow
$pingCmdLine = "ping -n 1 $ksCfgMgmtIP"
$i = 0
Do
{	
	$i += 1
	$pingOUT = ''; $pingOUT = Invoke-Expression -Command $pingCmdLine
	If ($pingOUT -like '*Request timed out*') {
		Write-Host "VMHost deployment successfully finished, server rebooted" -ForegroundColor Green
	} Else {
		Write-Progress -Activity "VMHost Deployment" -Status "[$i] Deployment is still in progress ..."
	}
	Start-Sleep -Seconds 60
}	While ($pingOUT -like '*Reply from*')

#endregion Waiting for New VMHost to reboot 2-nd time

#region Waiting for New VMHost to boot after deployment

Write-Host "`nWaiting for New VMHost to boot after deployment [~10] ..." -ForegroundColor Yellow
$pingCmdLine = "ping -n 1 $ksCfgMgmtIP"
$i = 0
Do
{	
	$i += 1
	$pingOUT = ''; $pingOUT = Invoke-Expression -Command $pingCmdLine
	If ($pingOUT -like '*Reply from*') {
		Write-Host "VMHost deployment finished, server booted" -ForegroundColor Green
	} Else {
		Write-Progress -Activity "VMHost Deployment" -Status "[$i - ~10] Server boot is in progress ..." `
		-PercentComplete ($i / 10 * 100 -as [int])
	}
	Start-Sleep -Seconds 60
}	While ($pingOUT -like '*Request timed out*')

#endregion Waiting for New VMHost to boot after deployment

#region Connect to New VMHost

Write-Host "`nConnecting to New VMHost ..." -ForegroundColor Yellow
$objVMHost = $null
$i = 0
Do 
{
	$i += 1
	$objVMHost = Connect-VIServer -Server $ksCfgVMHost -WarningAction SilentlyContinue -ErrorAction Stop
	If ($objVMHost) {
		Write-Host "Successfully connected to New VMHost" -ForegroundColor Green		
	} Else {
		Write-Progress -Activity "VMHost Deployment" -Status "[$i] Waiting for New VMHost to load all modules ..."
	}
	Start-Sleep -Seconds 30
} While (!$objVMHost)

#endregion Connect to New VMHost

#region Configure New VMHost

###
### Rename VMHost
###

Write-Host "`nRenaming New VMHost to '$VMHostBorn' ..." -ForegroundColor Yellow
$esxcli = $null
$renamed = $false
$esxcli = Get-EsxCli -VMHost $ksCfgVMHost -ErrorAction SilentlyContinue
If ($esxcli) {$renamed = $esxcli.system.hostname.set($null,$null,$VMHostBorn)}
If ($renamed) {
	Write-Host "New VMHost successfully renamed to '$VMHostBorn'" -ForegroundColor Green
} Else {Write-Host "Failed to rename New VMHost, remained generic '$ksCfgVMHost' hostname" -ForegroundColor DarkRed}

###
### Change vMotion IP
###

If ($vMotionIPv4 -ne '' -and $ksCfgvMoIP -ne '') {
	Write-Host "`nChanging vMotion IPv4 to $vMotionIPv4' ..." -ForegroundColor Yellow
	$vMoIP = $false
	If ($esxcli) {$vMoIP = $esxcli.network.ip.interface.ipv4.set("vmk2",$vMotionIPv4,$ksCfgvMoMask,$false,"static")}
	If ($vMoIP) {
		Write-Host "vMotion IP successfully changed to '$vMotionIPv4'" -ForegroundColor Green
	} Else {Write-Host "Failed to change vMotion IP, remained generic '$ksCfgvMoIP' IP" -ForegroundColor DarkRed}
}

###
### Change Mgmt IP (very last change !!!)
###

Write-Host "`nChanging Mgmt IPv4 to '$MgmtIPv4' ..." -ForegroundColor Yellow
$mgmtIP = $false
If ($esxcli) {$mgmtIP = $esxcli.network.ip.interface.ipv4.set("vmk0",$MgmtIPv4,$ksCfgMgmtMask,$false,"static")}
If ($mgmtIP) {
	Write-Host "Management IP successfully changed to '$MgmtIPv4'" -ForegroundColor Green
} Else {Write-Host "Failed to change Management IP, remained generic '$ksCfgMgmtIP' IP" -ForegroundColor DarkRed}

#endregion Configure New VMHost

#region Disconnect from New VMHost

Write-Host "`nDisconnecting from VMHost ..." -ForegroundColor Yellow
Disconnect-VIServer -Server "*" -Confirm:$false -Force:$true
If ($global:DefaultVIServers.Length -ne 0) {Write-Host "Failed to disconnect from VMHost" -ForegroundColor DarkRed}
Else {Write-Host "Successfully closed connections" -ForegroundColor Green}

#endregion Disconnect from New VMHost

#region Register New VMHost in DNS

If (!$dnsRecordA -and !$envBehindFW) {
	Write-Host "`nRegistering new A-record for '$VMHostBorn.$envDNSZone'" -ForegroundColor Yellow
	Add-DnsServerResourceRecordA -ComputerName $envDNSServer -ZoneName $envDNSZone -ErrorAction SilentlyContinue `
	-Name $VMHostBorn -IPv4Address $MgmtIPv4 -Confirm:$false -AllowUpdateAny:$false -CreatePtr
	
	$dnsRecordA = Get-DnsServerResourceRecord -ComputerName $envDNSServer `
	-ZoneName $envDNSZone -Name $VMHostBorn -RRType "A"
	If ($dnsRecordA) {
			Write-Host "DNS A-record for '$VMHostBorn.$envDNSZone' successfully created" -ForegroundColor Green		
	} Else {
		Write-Host "Sorry! Failed to create DNS A-record for '$VMHostBorn.$envDNSZone'" -ForegroundColor Yellow
	}
}

#endregion Register New VMHost in DNS

$Host.UI.RawUI.WindowTitle = $title
