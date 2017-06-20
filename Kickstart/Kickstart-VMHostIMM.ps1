#requires -Version 3.0
#requires -Modules 'DnsServer', 'VMware.VimAutomation.Core'

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
.PARAMETER CheckBusyIP
	Try to determine is Management and vMotion IP addresses
	are busy on the network by sending echo request.
.PARAMETER SaveBootOrder
	Save and restore original server's Boot Order after ESXi host deployment.
.PARAMETER Cred
	Rewrite VI Store Credentials.
.EXAMPLE
	PS C:\scripts> .\Kickstart-VMHostIMM.ps1 -IMMIP "10.1.99.120" -VMHostBorn esxdmz08 -ISO '\\cifs\share\ESXi-5.5.0-1331820-IBM-20131115.iso' -MgmtIPv4 "192.168.203.16" -Env DMZ -CheckBusyIP:$false -SaveBootOrder
	Deploy ESXi host in DMZ environment without vMotion and save original server's Boot Order.
.EXAMPLE
	PS C:\scripts> .\Kickstart-VMHostIMM.ps1 -IMM immprd11 -ESXi esxprd11 -MgmtIP "10.200.21.111" -vMotionIP "10.200.22.111"
	Deploy ESXi host in the default environment, use default ISO image.
.EXAMPLE
	PS C:\scripts> .\Kickstart-VMHostIMM.ps1 -IMMIPv4 '10.99.200.103' -VMHostBorn 'esxdmz03' -Env DMZ -MgmtIPv4 '10.200.21.211'
.EXAMPLE
	PS C:\scripts> .\Kickstart-VMHostIMM.ps1 -Cred
	Rewrite existing credentials in VI Credential Store.
.NOTES
	Author: Roman Gelman
	Version 1.0 :: 11-Aug-2015 :: [Release]
	Version 2.0 :: 06-Feb-2017 :: [Change]
	[1] The script is fully based on IMM-Module now.
	[2] Get-EsxCli -V2 supported.
.LINK
	https://ps1code.com/2015/08/27/kickstart-esxi-ibm-lenovo-powershell
#>

#region Parameters

[CmdletBinding(DefaultParameterSetName='DNS')]

Param (

	[Parameter(Mandatory,HelpMessage="IMM IPv4 Address",ParameterSetName='IP')]
		[Alias("IMMIP")]
	[ipaddress]$IMMIPv4
	,
	[Parameter(Mandatory,HelpMessage="IMM Hostname",ParameterSetName='DNS')]
		[ValidatePattern('^[A-Za-z\d_-]{1,15}$')]
		[Alias("IMM")]
	[string]$IMMHostname
	,
	[Parameter(Mandatory,HelpMessage="Deployed VMHost Hostname",ParameterSetName='DNS')]
	[Parameter(Mandatory,HelpMessage="Deployed VMHost Hostname",ParameterSetName='IP')]
		[ValidateNotNullorEmpty()]
		[Alias("ESXi")]
	[string]$VMHostBorn
	,
	[Parameter(Mandatory,HelpMessage="Kickstart prepared ESXi installation ISO file",ParameterSetName='IP')]
	[Parameter(Mandatory,HelpMessage="Kickstart prepared ESXi installation ISO file",ParameterSetName='DNS')]
		[ValidatePattern('\.iso$')]
		[ValidateScript({Test-Path -Path $_ -PathType Leaf})]
		[Alias("ISO")]
	[string]$KickstartISO
	,
	[Parameter(Mandatory,HelpMessage="Management VMKernel Port IPv4 address",ParameterSetName='IP')]
	[Parameter(Mandatory,HelpMessage="Management VMKernel Port IPv4 address",ParameterSetName='DNS')]
		[Alias ("MgmtIP")]
	[ipaddress]$MgmtIPv4
	,
	[Parameter(Mandatory=$false,HelpMessage="vMotion VMKernel Port IPv4 address",ParameterSetName='IP')]
	[Parameter(Mandatory=$false,HelpMessage="vMotion VMKernel Port IPv4 address",ParameterSetName='DNS')]
		[Alias ("vMotionIP")]
	[ipaddress]$vMotionIPv4
	,
	[Parameter(Mandatory=$false,HelpMessage="Virtual Environment",ParameterSetName='IP')]
	[Parameter(Mandatory=$false,HelpMessage="Virtual Environment",ParameterSetName='DNS')]
		[ValidateSet('PRD', 'DMZ')]
		[Alias ("Environment")]
	[string]$Env = 'PRD'
	,
	[Parameter(Mandatory=$false,HelpMessage="Try to ping Management and vMotion IP addresses",ParameterSetName='IP')]
	[Parameter(Mandatory=$false,HelpMessage="Try to ping Management and vMotion IP addresses",ParameterSetName='DNS')]
		[Alias ("CheckIP")]
	[boolean]$CheckBusyIP = $true
	,
	[Parameter(Mandatory=$false,HelpMessage="Save and restore original server's Boot Order",ParameterSetName='IP')]
	[Parameter(Mandatory=$false,HelpMessage="Save and restore original server's Boot Order",ParameterSetName='DNS')]
	[switch]$SaveBootOrder = $false
	,
	[Parameter(Mandatory=$false,HelpMessage="Rewrite VI Store Credentials",ParameterSetName='VIStoreCred')]
	[switch]$Cred
	
)

#endregion Parameters

#region Initialize Kickstart Configuration sets

$Host.UI.RawUI.WindowTitle = "Kickstart ESXi - [$VMHostBorn]"

Switch -exact ($Env) {
	
	'PRD'
	{
		$ksCfgVMHost   = 'esxprd00'
		$ksCfgRoot     = 'root'
		$ksCfgMgmtIP   = '10.200.21.160'
		$ksCfgMgmtMask = '255.255.255.0'
		$ksCfgvMoIP    = '10.200.22.160'
		$ksCfgvMoMask  = '255.255.255.0'
		$envDNSServer  = 'DNS21'
		$envDNSZone    = 'prod.contoso.local'
		$envBehindFW   = $false
		Break
	}
	'DMZ'
	{
		$ksCfgVMHost   = 'esxdmz00'
		$ksCfgRoot     = 'root'
		$ksCfgMgmtIP   = '192.168.203.15'
		$ksCfgMgmtMask = '255.255.255.240'
		$ksCfgvMoIP    = ''
		$envDNSServer  = 'DMZDNS34'
		$envDNSZone    = 'dmz.contoso.local'
		$envBehindFW   = $true
		Break
	}
}

$IMM = If ($PSCmdlet.ParameterSetName -eq 'DNS') {$IMMHostname} Else {$IMMIPv4.IPAddressToString}
$MgmtIPv4    = $MgmtIPv4.IPAddressToString
$vMotionIPv4 = $vMotionIPv4.IPAddressToString

#endregion Initialize Kickstart Configuration sets

#region Prerequisites

###
### Rewrite VI credentials store for New deployed VMHost
###

If ($PSCmdlet.ParameterSetName -eq 'VIStoreCred') {

	Write-Host "`nRewriting VI Credential Store item [$ksCfgVMHost-$ksCfgRoot] ..." -ForegroundColor Yellow

	$xxCred = $viCred = $null
	$xxUser = $xxPwd  = ''

	Do {$xxCred = Get-Credential -UserName $ksCfgRoot -Message "New VMHost $ksCfgRoot"} While (!$xxCred)

	If ($xxCred.Password.Length -lt 1) {
		Write-Host "Zero length root password is not allowed`n" -ForegroundColor Red; Exit 1
	} Else {
		$xxPwd  = $xxCred.GetNetworkCredential().Password
		$viCred = New-VICredentialStoreItem -Host $ksCfgVMHost -User $ksCfgRoot -Password $xxPwd
		If ($viCred) {Write-Host "VI Credentials Store item for [$ksCfgVMHost] VMHost successfully created`n" -ForegroundColor Green}
		Else {Write-Host "Failed to create VI Credentials Store item for [$ksCfgVMHost] VMHost`n" -ForegroundColor Red; Exit 1}
	}

	Exit 0
}

###
### DNS server check
###

If (!$envBehindFW) {
	$dnsCheck = Get-DnsServerZone -Name $envDNSZone -ComputerName $envDNSServer -ErrorAction SilentlyContinue
	If (!$dnsCheck) {Write-Host "Failed validate zone [$envDNSZone] on DNS server [$envDNSServer]" -ForegroundColor Red; Exit 1}
}

###
### Check VI credentials store for New deployed VMHost credentials
###

Write-Host "`nChecking VI Credential Store for [$ksCfgVMHost-$ksCfgRoot] credentials pair ..." -ForegroundColor Yellow
$viCred = $null
$viCred = Get-VICredentialStoreItem -Host $ksCfgVMHost -User $ksCfgRoot -ErrorAction SilentlyContinue
If (!$viCred) {
	Write-Host "[$ksCfgVMHost-$ksCfgRoot] credentials pair not found, please supply" -ForegroundColor Yellow
	
	$xxCred = $null
	$xxUser = $xxPwd = ''

	Do {$xxCred = Get-Credential -UserName $ksCfgRoot -Message "New VMHost $ksCfgRoot"} While (!$xxCred)

	If ($xxCred.Password.Length -lt 1) {
		Write-Host "Zero length root password is not allowed`n" -ForegroundColor Red; Exit 1
	} Else {
		$xxPwd  = $xxCred.GetNetworkCredential().Password
		$viCred = New-VICredentialStoreItem -Host $ksCfgVMHost -User $ksCfgRoot -Password $xxPwd
		If ($viCred) {Write-Host "VI Credentials Store item for [$ksCfgVMHost] VMHost successfully created" -ForegroundColor Green}
		Else {Write-Host "Failed to create VI Credentials Store item for [$ksCfgVMHost] VMHost" -ForegroundColor Red; Exit 1}
	}
} Else {
	Write-Host "Credential pair for Host [$ksCfgVMHost] :: User [$ksCfgRoot] already exists" -ForegroundColor Green
	Write-Host "To overwrite it, run this script with [-Cred] parameter" -ForegroundColor Green
}

###
### Check reply from initial IPv4 address of deployed VMHost (except environments that located behind firewalls)
###

If (!$envBehindFW) {

	If (Test-Connection -ComputerName $ksCfgMgmtIP -Count 1 -Quiet) {
		Write-Host "Initial IP address [$ksCfgMgmtIP] is busy on the network, deployment canceled`n" -ForegroundColor Red
		Exit 1
	}
}

###
### Check reply from Mgmt IPv4 address of deployed VMHost
###

If ($CheckBusyIP -and (!$envBehindFW)) {

	Write-Host "`nChecking Management IP ..." -ForegroundColor Yellow

	If (Test-Connection -ComputerName $MgmtIPv4 -Count 1 -Quiet) {
		Write-Host "IP address [$MgmtIPv4] is busy on the network, deployment canceled`n" -ForegroundColor Red
		Exit 1
	} Else {
		Write-Host "IP address [$MgmtIPv4] is not in use on the network" -ForegroundColor Green
	}
}

###
### Check reply from vMotion IPv4 address of deployed VMHost
###

If ($vMotionIPv4 -and $CheckBusyIP -and (!$envBehindFW)) {

	Write-Host "`nChecking vMotion IP ..." -ForegroundColor Yellow

	If (Test-Connection -ComputerName $vMotionIPv4 -Count 1 -Quiet) {
		Write-Host "IP address [$vMotionIPv4] is busy on the network, deployment canceled`n" -ForegroundColor Red
		Exit 1
	} Else {
		Write-Host "IP address [$vMotionIPv4] is not in use on the network" -ForegroundColor Green
	}
}

###
### Check DNS A-record, Exit only if A-record exists but not have the same IP address
###

If (!$envBehindFW) {
	Write-Host "`nChecking [$VMHostBorn] DNS A-record ..." -ForegroundColor Yellow
	$dnsRecordA = $null
	$dnsRecordA = Get-DnsServerResourceRecord -ComputerName $envDNSServer `
	-ZoneName $envDNSZone -Name $VMHostBorn -RRType "A" -ErrorAction SilentlyContinue
	If ($dnsRecordA) {
		If ($MgmtIPv4 -eq $dnsRecordA.RecordData.IPv4Address.IPAddressToString) {
			Write-Host "DNS A-record exists and matches to the IP address [$MgmtIPv4]" -ForegroundColor Green
		} Else {
			Write-Host "DNS A-record exists but not matches: VMHost:[$MgmtIPv4] | DNS:[$($dnsRecordA.RecordData.IPv4Address.IPAddressToString)]" -ForegroundColor Red
			Exit 1
		}
	} Else {
		Write-Host "DNS A-record for [$VMHostBorn] doesn't exist" -ForegroundColor Green
	}
}

###
### Get IMM credentials
###

$IMMLoginID = Get-IMMSupervisorCred -ClearText UserName
$IMMPwd     = Get-IMMSupervisorCred

$IMMBinding = " --host $IMM --user $IMMLoginID --password $IMMPwd"
$rdBinding  = " -s $IMM -l $IMMLoginID -p $IMMPwd"

###
### Save original Boot Order ###
###

If ($SaveBootOrder) {
	Write-Host "`nSaving original Boot Order ..." -ForegroundColor Yellow
	$OrigBO = Get-IMMServerBootOrder -IMM $IMM -IMMLogin $IMMLoginID -IMMPwd $IMMPwd
	Write-Host "Original Boot Order is: [$($OrigBO.Boot1)->$($OrigBO.Boot2)->$($OrigBO.Boot3)->$($OrigBO.Boot4)]" -ForegroundColor Green
}

###
### Change Boot Order: 'CD/DVD Rom' first
###

Write-Host "`nChanging Boot Order ..." -ForegroundColor Yellow
$DefaultBO = Set-IMMServerBootOrder -IMM $IMM -IMMLogin $IMMLoginID -IMMPwd $IMMPwd -Confirm:$false
Write-Host "Boot Order changed: [$($DefaultBO.Boot1)]->[$($DefaultBO.Boot2)]->[$($DefaultBO.Boot3)]->[$($DefaultBO.Boot4)]" -ForegroundColor Green

#endregion Prerequisites

#region Mount Kickstart ISO image with IBM Remote Disk CLI

###
### Unmount any virtual media from IMM if exists
###

Write-Host "`nUnmounting IMM Virtual Media drive ..." -ForegroundColor Yellow
If (Unmount-IMMISO -IMM $IMM) {Write-Host "Successfully unmounted" -ForegroundColor Green} Else {Write-Host "Nothing to unmount" -ForegroundColor Green}

###
### Mount ISO
###

Write-Host "`nMounting Kickstart ISO to IMM Virtual Media drive ..." -ForegroundColor Yellow
$immMount = Mount-IMMISO -IMM $IMM -IMMLogin $IMMLoginID -IMMPwd $IMMPwd -ISO $KickstartISO

If ($immMount.ISO) {
	Write-Host "Kickstart ISO file successfully mounted to IMM" -ForegroundColor Green
} Else {
	Write-Host "Failed to mount Kickstart ISO" -ForegroundColor Red
	Exit 1
}

#endregion Mount Kickstart ISO image with IBM Remote Disk CLI

#region PowerOn/Reboot server via IMM

Write-Host "`nBooting IBM/LENOVO server ..." -ForegroundColor Yellow

$InitialPowerState = (Get-IMMServerPowerState -IMM $IMM -IMMLogin $IMMLoginID -IMMPwd $IMMPwd).PowerState

$PowerState = Switch ($InitialPowerState) {
	'PoweredOff' {(Start-IMMServer -IMM $IMM -IMMLogin $IMMLoginID -IMMPwd $IMMPwd).PowerState; Break}
	'PoweredOn'  {(Reboot-IMMServerOS -IMM $IMM -IMMLogin $IMMLoginID -IMMPwd $IMMPwd -Confirm:$false).PowerState; Break}
	Default      {Write-Host "Unable to determine the server PowerState" -ForegroundColor Red; Exit 1}
}

Switch ($PowerState) {
	'Rebooted'  {Write-Host "Server rebooted successfully" -ForegroundColor Green; Break}
	'PoweredOn' {Write-Host "Server started successfully" -ForegroundColor Green; Break}
	Default     {Write-Host "Failed to boot the server" -ForegroundColor Red; Exit 1}
}

#endregion PowerOn/Reboot server via IMM

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
		$RevertBO = Set-IMMServerBootOrder -IMM $IMM -IMMLogin $IMMLoginID -IMMPwd $IMMPwd -Boot1 $OrigBO.Boot1 -Boot2 $OrigBO.Boot2 -Boot3 $OrigBO.Boot3 -Boot4 $OrigBO.Boot4
		If ($RevertBO.Boot1 -eq $OrigBO.Boot1) {
			Write-Host "Reverted successfully to: [$($OrigBO.Boot1)->$($OrigBO.Boot2)->$($OrigBO.Boot3)->$($OrigBO.Boot4)]`n" -ForegroundColor Green
		} Else {
			Write-Host "Sorry! Failed to revert to the Original Boot Order, please reconfigure manually`n" -ForegroundColor Red
		}
	}
	
	#endregion Revert Original Boot Order
	
	$pingOUT = ''; $pingOUT = Invoke-Expression -Command $pingCmdLine
	If ($pingOUT -like '*Reply from*') {
		Write-Host "First phase of VMHost deployment finished, server booted" -ForegroundColor Green
	} Else {
		Try
		{
			Write-Progress -Activity "VMHost Deployment [$VMHostBorn]" -Status "[$i] Deployment is in progress ..." `
						   -CurrentOperation "Boot Phase N$([char]186)1..3" -PercentComplete ($i / 30 * 100 -as [int]) -ErrorAction Stop
		} Catch {Write-Progress -Activity "Completed" -Completed}
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
		Try
		{
			Write-Progress -Activity "VMHost Deployment [$VMHostBorn]" -Status "[$i] Deployment is still in progress ..." `
						   -CurrentOperation "Boot Phase N$([char]186)2..3" -ErrorAction Stop
		} Catch {Write-Progress -Activity "Completed" -Completed}
	}
	Start-Sleep -Seconds 60
}	While ($pingOUT -like '*Reply from*')

#endregion Waiting for New VMHost to reboot 2-nd time

#region Waiting for New VMHost to boot after deployment

Write-Host "`nWaiting for New VMHost to boot after deployment [~10 min] ..." -ForegroundColor Yellow
$pingCmdLine = "ping -n 1 $ksCfgMgmtIP"
$i = 0
Do
{	
	$i += 1
	$pingOUT = ''; $pingOUT = Invoke-Expression -Command $pingCmdLine
	If ($pingOUT -like '*Reply from*') {
		Write-Host "VMHost deployment finished, server booted" -ForegroundColor Green
	} Else {
		Try
		{
			Write-Progress -Activity "VMHost Deployment [$VMHostBorn]" -Status "[$i .. ~10] Server boot is in progress ..." `
						   -CurrentOperation "Boot Phase N$([char]186)3..3" -PercentComplete ($i / 10 * 100 -as [int]) -ErrorAction Stop
		} Catch {Write-Progress -Activity "Completed" -Completed}
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
		Try
		{
			Write-Progress -Activity "VMHost Deployment [$VMHostBorn]" -Status "[$i] Waiting for New VMHost to load all modules ..." `
			-CurrentOperation "Finishing deployment" -ErrorAction Stop
		} Catch {Write-Progress -Activity "Completed" -Completed}
	}
	Start-Sleep -Seconds 30
} While (!$objVMHost)

#endregion Connect to New VMHost

#region Configure New VMHost

###
### Rename VMHost
###

Write-Host "`nRenaming New VMHost to [$VMHostBorn] ..." -ForegroundColor Yellow
$esxcli = $null
$renamed = $false
$esxcli = Get-EsxCli -VMHost $ksCfgVMHost -ErrorAction SilentlyContinue -V2
If ($esxcli) {$renamed = $esxcli.system.hostname.set.Invoke(@{'domain'=$envDNSZone;'host'=$VMHostBorn})}
If ($renamed) {
	Write-Host "New VMHost successfully renamed to [$VMHostBorn]" -ForegroundColor Green
} Else {Write-Host "Failed to rename New VMHost, remained generic [$ksCfgVMHost] hostname" -ForegroundColor Red}

###
### Change vMotion IP
###

If ($vMotionIPv4 -and $ksCfgvMoIP) {
	Write-Host "`nChanging vMotion IPv4 to [vMotionIPv4] ..." -ForegroundColor Yellow
	$vMoIP = $false
	If ($esxcli) {$vMoIP = $esxcli.network.ip.interface.ipv4.set.Invoke(@{'interfacename'='vmk2';'ipv4'=$vMotionIPv4;'netmask'=$ksCfgvMoMask;'type'='static'})}
	If ($vMoIP) {
		Write-Host "vMotion IP successfully changed to [$vMotionIPv4]" -ForegroundColor Green
	} Else {Write-Host "Failed to change vMotion IP, remained generic [$ksCfgvMoIP] IP" -ForegroundColor Red}
}

###
### Change Mgmt IP (very last change !!!)
###

Write-Host "`nChanging Mgmt IPv4 to [$MgmtIPv4] ..." -ForegroundColor Yellow
$mgmtIP = $false
If ($esxcli) {$mgmtIP = $esxcli.network.ip.interface.ipv4.set.Invoke(@{'interfacename'='vmk0';'ipv4'=$MgmtIPv4;'netmask'=$ksCfgMgmtMask;'type'='static'})}
If ($mgmtIP) {
	Write-Host "Management IP successfully changed to [$MgmtIPv4]" -ForegroundColor Green
} Else {Write-Host "Failed to change Management IP, remained generic [$ksCfgMgmtIP] IP" -ForegroundColor Red}

#endregion Configure New VMHost

#region Disconnect from New VMHost

Write-Host "`nDisconnecting from VMHost ..." -ForegroundColor Yellow
Disconnect-VIServer -Server "*" -Confirm:$false -Force:$true
If ($global:DefaultVIServers.Length -ne 0) {Write-Host "Failed to disconnect from VMHost" -ForegroundColor Red}
Else {Write-Host "Successfully closed connections" -ForegroundColor Green}

#endregion Disconnect from New VMHost

#region Register New VMHost in DNS

If (!$dnsRecordA -and !$envBehindFW) {
	Write-Host "`nRegistering new A-record [$VMHostBorn.$envDNSZone]" -ForegroundColor Yellow
	Add-DnsServerResourceRecordA -ComputerName $envDNSServer -ZoneName $envDNSZone -ErrorAction SilentlyContinue `
	-Name $VMHostBorn -IPv4Address $MgmtIPv4 -Confirm:$false -AllowUpdateAny:$false -CreatePtr
	
	$dnsRecordA = Get-DnsServerResourceRecord -ComputerName $envDNSServer `
	-ZoneName $envDNSZone -Name $VMHostBorn -RRType "A"
	If ($dnsRecordA) {
		Write-Host "DNS A-record for [$VMHostBorn.$envDNSZone] successfully created`n" -ForegroundColor Green		
	} Else {
		Write-Host "Failed to create DNS A-record for [$VMHostBorn.$envDNSZone->$MgmtIPv4]`n" -ForegroundColor Red
	}
}

#endregion Register New VMHost in DNS
