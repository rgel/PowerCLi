Class VAMI { } #EndClass VAMI

Class VamiService: VAMI
{
	[ValidateNotNullOrEmpty()][string]$Server
	[ValidateNotNullOrEmpty()][string]$Name
	[string]$Description
	[ValidateNotNullOrEmpty()][string]$State
	[string]$Health
	[ValidateNotNullOrEmpty()][string]$Startup
	
	[string] ToString () { return "$($this.Name)" }
	[string] GetServer () { return "$($this.Server)" }
	
} #EndClass VamiService


Function Get-VAMISummary
{
	
<#
.SYNOPSIS
    Get basic VCSA summary and version info.
.DESCRIPTION
	This function retrieves some basic information from VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMISummary
.NOTES
	Created by  :: William Lam @lamw (http://www.virtuallyghetto.com/2017/01/exploring-new-vcsa-vami-api-wpowercli-part-1.html)
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 29-Mar-2017 :: [Release] :: Publicly available
	Version 1.1 :: 07-Dec-2017 :: [Feature] :: New properties added: Release, ReleaseDate, BackupExpireDate, DaysToExpire
	Version 1.2 :: 21-Dec-2017 :: [Change] :: Release [6.5.0 U1d] added
	Version 1.3 :: 21-Jan-2018 :: [Change] :: Release [6.5.0 U1e] added
	Version 1.4 :: 29-Apr-2018 :: [Change] :: Release [6.5.0 U1g] added
	Version 1.5 :: 12-Jul-2018 :: [Change] :: Two [6.5.0 U2] Releases added
	Version 2.0 :: 16-Jan-2019 :: [Build] :: The BackupExpireDate and DaysToExpire properties replaced by IsExpired, VCSA 6.7 supported
.LINK
	https://ps1code.com/2017/12/10/vcsa-backup-expiration-powercli
#>
	$ErrorActionPreference = 'Stop'
	
	foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
	{
		Try
		{
			$SystemVersionAPI = Get-CisService -Name 'com.vmware.appliance.system.version' -Server $Server -Verbose:$false
			$VersionInfo = $SystemVersionAPI.get() | select product, 'type', version, build, install_time
			$FullVersion = [version]$VersionInfo.version
			$Version = "$($FullVersion.Major).$($FullVersion.Minor)"
			
			$ReleaseInfo = switch -exact ($Version)
			{
				'6.5'
				{
					switch -exact ($VersionInfo.build)
					{
						### Official expiration dates regarding to the KB51124 ###
						'4602587' { @{ 'Expired' = $true; 'Release' = '6.5.GA'; 'ReleaseDate' = '11/15/2016' } }
						'4944578' { @{ 'Expired' = $true; 'Release' = '6.5.a'; 'ReleaseDate' = '02/02/2017' } }
						'5178943' { @{ 'Expired' = $true; 'Release' = '6.5.b'; 'ReleaseDate' = '03/14/2017' } }
						'5318112' { @{ 'Expired' = $true; 'Release' = '6.5.c'; 'ReleaseDate' = '04/13/2017' } }
						'5318154' { @{ 'Expired' = $true; 'Release' = '6.5.d'; 'ReleaseDate' = '04/18/2017' } }
						'5705665' { @{ 'Expired' = $true; 'Release' = '6.5.e'; 'ReleaseDate' = '06/15/2017' } }
						'5973321' { @{ 'Expired' = $true; 'Release' = '6.5 U1'; 'ReleaseDate' = '07/27/2017' } }
						'6671409' { @{ 'Expired' = $true; 'Release' = '6.5 U1a'; 'ReleaseDate' = '09/21/2017' } }
						'6816762' { @{ 'Expired' = $true; 'Release' = '6.5 U1b'; 'ReleaseDate' = '10/26/2017' } }
						### Root password expiration issue has resolved starting from Update 1c release ###
						'7119070' { @{ 'Expired' = $false; 'Release' = '6.5.f'; 'ReleaseDate' = '11/14/2017' } }
						'7119157' { @{ 'Expired' = $false; 'Release' = '6.5 U1c'; 'ReleaseDate' = '11/14/2017' } }
						'7312210' { @{ 'Expired' = $false; 'Release' = '6.5 U1d'; 'ReleaseDate' = '12/19/2017' } }
						'7515524' { @{ 'Expired' = $false; 'Release' = '6.5 U1e'; 'ReleaseDate' = '01/09/2018' } }
						'8024368' { @{ 'Expired' = $false; 'Release' = '6.5 U1g'; 'ReleaseDate' = '03/20/2018' } }
						'8307201' { @{ 'Expired' = $false; 'Release' = '6.5 U2'; 'ReleaseDate' = '05/03/2018' } }
						'8815520' { @{ 'Expired' = $false; 'Release' = '6.5 U2b'; 'ReleaseDate' = '06/28/2018' } }
						'9451637' { @{ 'Expired' = $false; 'Release' = '6.5 U2c'; 'ReleaseDate' = '08/14/2018' } }
						'10964411' { @{ 'Expired' = $false; 'Release' = '6.5 U2d'; 'ReleaseDate' = '11/29/2018' } }
						default { @{ 'Expired' = $false; 'Release' = '6.5 U?'; 'ReleaseDate' = (Get-Date) } }
					}
				}
				'6.7'
				{
					switch -exact ($VersionInfo.build)
					{
						'8546234' { @{ 'Expired' = $false; 'Release' = '6.7.a'; 'ReleaseDate' = '05/22/2018' } }
						'8832884' { @{ 'Expired' = $false; 'Release' = '6.7.b'; 'ReleaseDate' = '06/28/2018' } }
						'9232925' { @{ 'Expired' = $false; 'Release' = '6.7.c'; 'ReleaseDate' = '07/26/2018' } }
						'9451876' { @{ 'Expired' = $false; 'Release' = '6.7.d'; 'ReleaseDate' = '08/14/2018' } }
						'10244745' { @{ 'Expired' = $false; 'Release' = '6.7 U1'; 'ReleaseDate' = '10/16/2018' } }
						default { @{ 'Expired' = $false; 'Release' = '6.7 U?'; 'ReleaseDate' = (Get-Date) } }
					}
				}
				default { @{ 'Expired' = $false; 'Release' = '?'; 'ReleaseDate' = (Get-Date) } }
			}
			$SystemUptimeAPI = Get-CisService -Name 'com.vmware.appliance.system.uptime' -Server $Server -Verbose:$false
			$ts = [timespan]::FromSeconds($SystemUptimeAPI.get().ToString())
			$uptime = $ts.ToString("dd\ \D\a\y\s\,\ hh\:mm\:ss")
			
			[pscustomobject] @{
				Server = $Server.Name
				Product = $VersionInfo.product
				Type = $VersionInfo.type.Replace('Platform Services Controller', 'PSC')
				Version = $Version
				FullVersion = $FullVersion
				Build = [uint32]$VersionInfo.build
				Release = $ReleaseInfo.Release
				ReleaseDate = Get-Date $ReleaseInfo.ReleaseDate
				InstallDate = ([datetime]($VersionInfo.install_time -replace '[a-zA-Z]', ' ')).ToLocalTime()
				IsExpired = $ReleaseInfo.Expired
				Uptime = $uptime
			}
		}
		Catch {  }
	}
	
} #EndFunction Get-VAMISummary

Function Get-VAMIHealth
{
	
<#
.SYNOPSIS
    This function retrieves health information from VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
    Function to return VAMI health.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMIHealth
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 29-Mar-2017 :: [Release] :: Publicly available
	Version 1.1 :: 19-Apr-2017 :: [Change] :: 'HealthLastCheck' property converted to the Universal time
.LINK
	http://www.virtuallyghetto.com/2017/01/exploring-new-vcsa-vami-api-wpowercli-part-2.html
#>
	
	$ErrorActionPreference = 'Stop'
	foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
	{
		Try
		{
			$healthOverall = (Get-CisService -Name 'com.vmware.appliance.health.system' -Server $Server).get()
			$healthLastCheck = (Get-CisService -Name 'com.vmware.appliance.health.system' -Server $Server).lastcheck()
			$healthCPU = (Get-CisService -Name 'com.vmware.appliance.health.load' -Server $Server).get()
			$healthMem = (Get-CisService -Name 'com.vmware.appliance.health.mem' -Server $Server).get()
			$healthSwap = (Get-CisService -Name 'com.vmware.appliance.health.swap' -Server $Server).get()
			$healthStorage = (Get-CisService -Name 'com.vmware.appliance.health.storage' -Server $Server).get()
			
			# DB health only applicable for Embedded/External VCSA Node
			$vami = (Get-CisService -Name 'com.vmware.appliance.system.version' -Server $Server).get()
			
			if ("vCenter Server with an embedded Platform Services Controller", "vCenter Server with an external Platform Services Controller" -contains $vami.type)
			{
				$healthVCDB = (Get-CisService -Name 'com.vmware.appliance.health.databasestorage' -Server $Server).get()
			}
			else
			{
				$healthVCDB = "N/A on PSC node"
			}
			$healthSoftwareUpdates = (Get-CisService -Name 'com.vmware.appliance.health.softwarepackages' -Server $Server).get()
			
			$healthResult = [pscustomobject] @{
				Server = $Server.Name
				HealthOverall = (Get-Culture).TextInfo.ToTitleCase($healthOverall)
				HealthLastCheck = (Get-Date $healthLastCheck).ToUniversalTime()
				HealthCPU = (Get-Culture).TextInfo.ToTitleCase($healthCPU)
				HealthMem = (Get-Culture).TextInfo.ToTitleCase($healthMem)
				HealthSwap = (Get-Culture).TextInfo.ToTitleCase($healthSwap)
				HealthStorage = (Get-Culture).TextInfo.ToTitleCase($healthStorage)
				HealthVCDB = (Get-Culture).TextInfo.ToTitleCase($healthVCDB)
				HealthSoftware = (Get-Culture).TextInfo.ToTitleCase($healthSoftwareUpdates)
			}
			$healthResult
		}
		Catch { }
	}
	
} #EndFunction Get-VAMIHealth

Function Get-VAMIAccess
{
	
<#
.SYNOPSIS
    Get VAMI access interfaces (Console, DCUI, Bash Shell & SSH).
.DESCRIPTION
    This function retrieves access information from VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMIAccess
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 29-Mar-2017 :: [Release] :: Publicly available
	Version 1.1 :: 14-Jan-2019 :: [Change] :: Added 'BashDisable' property
.LINK
	http://www.virtuallyghetto.com/2017/01/exploring-new-vcsa-vami-api-wpowercli-part-3.html
#>
	
	$ErrorActionPreference = 'Stop'
	
	foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
	{
		Try
		{
			$consoleAccess = (Get-CisService -Name 'com.vmware.appliance.access.consolecli' -Server $Server).get()
			$dcuiAccess = (Get-CisService -Name 'com.vmware.appliance.access.dcui' -Server $Server).get()
			$shellAccess = (Get-CisService -Name 'com.vmware.appliance.access.shell' -Server $Server).get()
			$sshAccess = (Get-CisService -Name 'com.vmware.appliance.access.ssh' -Server $Server).get()
			
			[pscustomobject] @{
				Server = $Server.Name
				Console = $consoleAccess
				DCUI = $dcuiAccess
				BashShell = $shellAccess.enabled
				BashDisable = (Get-Date).AddSeconds($shellAccess.timeout)
				SSH = $sshAccess
			}
		}
		Catch { }
	}
	
} #EndFunction Get-VAMIAccess

Function Set-VAMIAccess
{
	
<#
.SYNOPSIS
    Enable/disable VCSA access interfaces (Console, DCUI, Bash Shell & SSH).
.DESCRIPTION
    This function enables or disables VCSA access interfaces from VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.PARAMETER Interface
	Specifies access interface(s).
.PARAMETER Access
	Specifies selected interfaces state, enabled or disabled.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Set-VAMIAccess -Interface SSH -Access Enable
	Enable SSH access to appliance.
.EXAMPLE
	PS C:\> Set-VAMIAccess SSH,Console Disable -Confirm:$false
	Silently disable multiple access interfaces.
.EXAMPLE
	PS C:\> Set-VAMIAccess SSH,Console,BashShell,DCUI
	Enable all possible interfaces. Note, the BashShell disallowed after 24H, the counter is 'BashDisable' property.
.NOTES
	Author      :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 15-Jan-2019 :: [Release] :: Publicly available
.LINK
	https://code.vmware.com/apis/60/vcenter-server-appliance-management
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	Param (
		[Parameter(Mandatory, Position = 0)]
		[ValidateSet('SSH', 'DCUI', 'BashShell', 'Console')]
		[string[]]$Interface
		 ,
		[Parameter(Position = 1)]
		[ValidateSet('Enable', 'Disable')]
		[string]$Access = 'Enable'
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$Set = if ($Access -eq 'Enable') { $true } else { $false }
		$hashInt = @{
			'SSH' = 'ssh';
			'DCUI' = 'dcui';
			'BashShell' = 'shell';
			'Console' = 'consolecli';
		}
	}
	Process
	{
		foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
		{
			foreach ($Int in $Interface)
			{
				if ($PSCmdlet.ShouldProcess("VCSA [$($Server.Name)]", "$Access [$Int] interface"))
				{
					Try
					{
						$AccessAPI = Get-CisService -Name "com.vmware.appliance.access.$($hashInt.$Int)" -Server $Server -Verbose:$false
						
						if ($Int -ne 'BashShell')
						{
							$AccessAPI.set($Set)
						}
						else
						{
							$ShellConfig = $AccessAPI.Help.set.config.Create()
							$ShellConfig.enabled = $Set
							$ShellConfig.timeout = 86400
							$AccessAPI.set($ShellConfig)
						}
					}
					Catch { }
				}
			}
			Get-VAMIAccess | Where-Object { $_.Server -eq $Server.Name }
		}
	}
	End { }
	
} #EndFunction Set-VAMIAccess

Function Get-VAMITime
{
	
<#
.SYNOPSIS
    This function retrieves the time and NTP info from VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
    Function to return current Time and NTP information.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMITime
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 29-Mar-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/01/exploring-new-vcsa-vami-api-wpowercli-part-4.html
#>
	
	$ErrorActionPreference = 'Stop'
	foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
	{
		Try
		{
			$systemTimeAPI = Get-CisService -Name 'com.vmware.appliance.system.time' -Server $Server
			$timeResults = $systemTimeAPI.get()
			
			$timeSync = (Get-CisService -Name 'com.vmware.appliance.techpreview.timesync' -Server $Server).get()
			$timeSyncMode = $timeSync.mode
			
			$timeResult = [pscustomobject] @{
				Server = $Server.Name
				Timezone = $timeResults.timezone
				Date = $timeResults.date
				CurrentTime = $timeResults.time
				Mode = $timeSyncMode
				NTPServers = "N/A"
				NTPStatus = "N/A"
			}
			
			if ($timeSyncMode -eq "NTP")
			{
				$ntpServers = (Get-CisService -Name 'com.vmware.appliance.techpreview.ntp' -Server $Server).get()
				$timeResult.NTPServers = $ntpServers.servers -join ', '
				$timeResult.NTPStatus = $ntpServers.status
			}
			$timeResult
		}
		Catch { }
	}
	
} #EndFunction Get-VAMITime

Function Get-VAMINetwork
{
	
<#
.SYNOPSIS
    This function retrieves network information from VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
    Function to return networking information including details for each interface.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMINetwork
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 29-Mar-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/02/exploring-new-vcsa-vami-api-wpowercli-part-5.html
#>
	$ErrorActionPreference = 'Stop'
	foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
	{
		Try
		{
			$netResults = @()
			
			$Hostname = (Get-CisService -Name 'com.vmware.appliance.networking.dns.hostname' -Server $Server).get()
			$dns = (Get-CisService -Name 'com.vmware.appliance.networking.dns.servers' -Server $Server).get()
			
			$interfaces = (Get-CisService -Name 'com.vmware.appliance.networking.interfaces' -Server $Server).list()
			foreach ($interface in $interfaces)
			{
				$ipv4API = (Get-CisService -Name 'com.vmware.appliance.techpreview.networking.ipv4' -Server $Server)
				$spec = $ipv4API.Help.get.interfaces.CreateExample()
				$spec += $interface.name
				$ipv4result = $ipv4API.get($spec)
				
				$interfaceResult = [pscustomobject] @{
					Server = $Server.Name
					FQDN = $Hostname
					DNS = $dns.servers -join ', '
					Inteface = $interface.name
					MAC = $interface.mac
					Status = (Get-Culture).TextInfo.ToTitleCase($interface.status)
					Mode = "$($ipv4result.mode)" -replace '^is_', ''
					IP = "$($ipv4result.address)/$($ipv4result.prefix)"
					Gateway = $ipv4result.default_gateway
					Updateable = $ipv4result.updateable
				}
				$netResults += $interfaceResult
			}
			$netResults
		}
		Catch { }
	}
	
} #EndFunction Get-VAMINetwork

Function Get-VAMIDisks
{
	
<#
.SYNOPSIS
    This function retrieves VMDK disk number to partition mapping VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
    Function to return VMDK disk number to OS partition mapping
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMIDisks
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 29-Mar-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/02/exploring-new-vcsa-vami-api-wpowercli-part-6.html
#>
	$ErrorActionPreference = 'Stop'
	foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
	{
		Try
		{
			$storageAPI = Get-CisService -Name 'com.vmware.appliance.system.storage' -Server $Server
			$disks = $storageAPI.list()
			
			foreach ($disk in $disks | sort { [int]$_.disk.ToString() })
			{
				$storageResult = [pscustomobject] @{
					Server = $Server.Name
					Disk = $disk.disk
					Partition = $disk.partition
				}
				$storageResult
			}
		}
		Catch { }
	}
	
} #EndFunction Get-VAMIDisks


Function Start-VAMIDiskResize
{
	
<#
.SYNOPSIS
    This function triggers an OS partition resize after adding additional disk capacity
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
    Function triggers OS partition resize operation.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Start-VAMIDiskResize -Server 192.168.1.51 -Verbose
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 02-Apr-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/02/exploring-new-vcsa-vami-api-wpowercli-part-6.html
#>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory)]
		[string]$Server
	)
	
	Begin
	{
		If (!($CisServer = $global:DefaultCisServers | ? { $_.Name -eq $Server -and $_.IsConnected })) {Throw "VAMI Server [$Server] is not connected"}
	}
	
	Process
	{
		Try
		{
			$storageAPI = Get-CisService -Name 'com.vmware.appliance.system.storage' -Server $CisServer -Verbose:$false
			Write-Verbose "Initiated OS partition resize operation on VAMI Server [$Server] ..."
			$storageAPI.resize()
			Write-Verbose "Resize operation on VAMI Server [$Server] succeeded"
		}
		Catch
		{
			Write-Verbose "Failed to resize OS partitions on VAMI Server [$Server]"
		}
	}
	
} #EndFunction Start-VAMIDiskResize

Function Get-VAMIStatsList
{
	
<#
.SYNOPSIS
    This function retrieves list avialable monitoring metrics in VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
    Function to return list of available monitoring metrics that can be queried.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMIStatsList
.EXAMPLE
    PS C:\> Get-VAMIStatsList -Category Memory
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 02-Apr-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/02/exploring-new-vcsa-vami-api-wpowercli-part-7.html
#>
	
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateSet("CPU", "Memory", "Network", "Storage", "All")]
		[string]$Category = 'All'
	)
	
	$StatsCategory = switch -exact ($Category)
	{
		"CPU" { '^cpu\.' }
		"Memory" { '^mem\.' }
		"Network" { '^net\.' }
		"Storage" { '^storage\.' }
		"All" {'.'}
	}
	
	Try
	{
		$monitoringAPI = Get-CisService -Name 'com.vmware.appliance.monitoring' -Server $global:DefaultCisServers[0]
		$ids = $monitoringAPI.list() | select id, units | sort -Property id
		
		foreach ($id in $ids)
		{
			$id | ? { $_.id -match $StatsCategory }
		}
	}
	Catch { }
	
} #EndFunction Get-VAMIStatsList

Function Get-VAMIStorageUsed
{
	
<#
.SYNOPSIS
    This function retrieves the individaul OS partition storage utilization
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
    Function to return individual OS partition storage utilization.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMIStorageUsed
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 29-Mar-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/02/exploring-new-vcsa-vami-api-wpowercli-part-7.html
#>
	
	$ErrorActionPreference = 'Stop'
	foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
	{
		Try
		{
			$monitoringAPI = Get-CisService 'com.vmware.appliance.monitoring' -Server $Server
			$querySpec = $monitoringAPI.help.query.item.CreateExample()
			
			# List of IDs from Get-VAMIStatsList to query
			$querySpec.Names = @(
				"storage.used.filesystem.autodeploy",
				"storage.used.filesystem.boot",
				"storage.used.filesystem.coredump",
				"storage.used.filesystem.imagebuilder",
				"storage.used.filesystem.invsvc",
				"storage.used.filesystem.log",
				"storage.used.filesystem.netdump",
				"storage.used.filesystem.root",
				"storage.used.filesystem.updatemgr",
				"storage.used.filesystem.vcdb_core_inventory",
				"storage.used.filesystem.vcdb_seat",
				"storage.used.filesystem.vcdb_transaction_log",
				"storage.totalsize.filesystem.autodeploy",
				"storage.totalsize.filesystem.boot",
				"storage.totalsize.filesystem.coredump",
				"storage.totalsize.filesystem.imagebuilder",
				"storage.totalsize.filesystem.invsvc",
				"storage.totalsize.filesystem.log",
				"storage.totalsize.filesystem.netdump",
				"storage.totalsize.filesystem.root",
				"storage.totalsize.filesystem.updatemgr",
				"storage.totalsize.filesystem.vcdb_core_inventory",
				"storage.totalsize.filesystem.vcdb_seat",
				"storage.totalsize.filesystem.vcdb_transaction_log"
			)
			
			# Tuple (Filesystem Name, Used, Total) to store results
			$storageStats = @{
				"autodeploy" = @{ "name" = "/storage/autodeploy"; "used" = 0; "total" = 0 };
				"boot" = @{ "name" = "/boot"; "used" = 0; "total" = 0 };
				"coredump" = @{ "name" = "/storage/core"; "used" = 0; "total" = 0 };
				"imagebuilder" = @{ "name" = "/storage/imagebuilder"; "used" = 0; "total" = 0 };
				"invsvc" = @{ "name" = "/storage/invsvc"; "used" = 0; "total" = 0 };
				"log" = @{ "name" = "/storage/log"; "used" = 0; "total" = 0 };
				"netdump" = @{ "name" = "/storage/netdump"; "used" = 0; "total" = 0 };
				"root" = @{ "name" = "/"; "used" = 0; "total" = 0 };
				"updatemgr" = @{ "name" = "/storage/updatemgr"; "used" = 0; "total" = 0 };
				"vcdb_core_inventory" = @{ "name" = "/storage/db"; "used" = 0; "total" = 0 };
				"vcdb_seat" = @{ "name" = "/storage/seat"; "used" = 0; "total" = 0 };
				"vcdb_transaction_log" = @{ "name" = "/storage/dblog"; "used" = 0; "total" = 0 }
			}
			
			$querySpec.interval = "DAY1"
			$querySpec.function = "MAX"
			$querySpec.start_time = ((Get-Date).AddDays(-1))
			$querySpec.end_time = (Get-Date)
			$queryResults = $monitoringAPI.query($querySpec) | select * -ExcludeProperty Help
			
			foreach ($queryResult in $queryResults)
			{
				# Update hash if its used storage results
				if ($queryResult.name -match "used")
				{
					$key = (($queryResult.name).ToString()).Split(".")[-1]
					$value = [Math]::Round([int]($queryResult.data[1]).ToString()/1MB, 2)
					$storageStats[$key]["used"] = $value
					# Update hash if its total storage results
				}
				else
				{
					$key = (($queryResult.name).ToString()).Split(".")[-1]
					$value = [Math]::Round([int]($queryResult.data[1]).ToString()/1MB, 2)
					$storageStats[$key]["total"] = $value
				}
			}
			
			$storageResults = @()
			foreach ($key in $storageStats.keys | sort -Property name)
			{
				$Total = $storageStats[$key].total
				$Used = $storageStats[$key].used
				$Usage = If ($Total -ne 0) {[Math]::Round($Used*100/$Total,1)} Else {0}
				
				$statResult = [pscustomobject] @{
					Server = $Server.Name
					Filesystem = $storageStats[$key].name
					TotalGB = $Total
					UsedGB = $Used
					'Usage%' = $Usage
				}
				$storageResults += $statResult
			}
			$storageResults |sort Server,Filesystem
		}
		Catch { }
	}
	
} #EndFunction Get-VAMIStorageUsed

Function Get-VAMIPerformance
{
	
<#
.SYNOPSIS
    This function retrieves the CPU & Memory usage for a certain period
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
    Function to return CPU% & Memory% usage.
.PARAMETER Period
	Specifies period to collect performance data.
.PARAMETER Interval
	Specifies interval between data samples.
.PARAMETER Counter
	Specifies performance counter type.
.PARAMETER ExcludeZero
	If specified, does not return samples that equal to zero.
	Probably the appliance was powered off or before deployment.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMIPerformance
.EXAMPLE
	PS C:\> Get-VAMIPerformance -Interval HOURS6
.EXAMPLE
	PS C:\> Get-VAMIPerformance Month MINUTES30 AVG
.EXAMPLE	
	PS C:\> Get-VAMIPerformance -Interval HOURS2 -Period Quarter -ExcludeZero |epcsv -notype .\Perf.csv
.NOTES
	Idea        :: William Lam @lamw
	Created by  :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 04-Apr-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/02/exploring-new-vcsa-vami-api-wpowercli-part-7.html
#>
	
	Param (
		[Parameter(Mandatory = $false, Position = 0)]
		[ValidateSet("Day", "Week", "Month", "Quarter")]
		[string]$Period = 'Day'
		 ,
		[Parameter(Mandatory = $false, Position = 1)]
		[ValidateSet("MINUTES5", "MINUTES30", "HOURS2", "HOURS6", "DAY1")]
		[string]$Interval = 'HOURS2'
		 ,
		[Parameter(Mandatory = $false, Position = 2)]
		[ValidateSet("MAX", "AVG", "MIN")]
		[string]$Counter = 'MAX'
		 ,
		[Parameter(Mandatory = $false)]
		[switch]$ExcludeZero
	)
	
	$formatString = "00.00"
	
	$tsMin = switch ($Interval)
	{
		'MINUTES5' { 5 }
		'MINUTES30' { 30 }
		'HOURS2' { 120 }
		'HOURS6' { 360 }
		'DAY1' { 1440 }
	}
	
	$endTime = Get-Date
	
	$startTime = switch ($Period)
	{
		'Day'	{ $endTime.AddDays(-1) }
		'Week' { $endTime.AddDays(-7) }
		'Month' { $endTime.AddMonths(-1) }
		'Quarter' { $endTime.AddMonths(-3) }
	}
	
	$ErrorActionPreference = 'Stop'
	foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
	{
		Try
		{
			$monitoringAPI = Get-CisService 'com.vmware.appliance.monitoring' -Server $Server
			$querySpec = $monitoringAPI.help.query.item.CreateExample()
			
			# List of IDs from Get-VAMIStatsList to query
			$querySpec.Names = @((Get-VAMIStatsList).id -match '^(cpu|mem)\.')
			
			$querySpec.interval = $Interval
			$querySpec.function = $Counter
			$querySpec.start_time = $startTime
			$querySpec.end_time = $endTime
			$queryResults = $monitoringAPI.query($querySpec) | select * -ExcludeProperty Help
			$sampleCount = ($queryResults[0].data).Count
		
			foreach ($queryResult in $queryResults)
			{
				switch -regex ($queryResult.name)
				{
					'^cpu\.util' { $perfDataCpu = $queryResult.data }
					'^mem\.util' { $perfDataMem = $queryResult.data }
					'^mem\.total' { for ($k = 0; $k -lt $sampleCount; $k++) { do { $totalMem = $queryResult.data[$k] } while ($totalMem -eq 0) } }
				}
			}

			$perfResults = @()
			$TimeStamp = $startTime.AddMinutes(-$tsMin)

			for ($i = 0; $i -lt $sampleCount; $i++)
			{
				$TimeStamp = $TimeStamp.AddMinutes($tsMin)
			
				$perfResult = [pscustomobject] @{
					Server = $Server.Name
					'CPU%' = ([Math]::Round($perfDataCpu[$i], 2)).ToString($formatString)
					'Memory%' = if ($totalMem) { ([Math]::Round(($perfDataMem[$i] -as [int32]) * 100/$totalMem, 2)).ToString($formatString) } else {'N/A'}
					Timestamp = $TimeStamp.ToString('dd/MM/yyyy HH:mm:ss')
				}
			
				if ($PSBoundParameters.ContainsKey('ExcludeZero'))
				{
					if ($perfResult.'CPU%', $perfResult.'Memory%' -notcontains $formatString) { $perfResults += $perfResult }
				}
				else
				{
					$perfResults += $perfResult
				}
			}
		$perfResults
		}		
		Catch { }
	}
	
} #EndFunction Get-VAMIPerformance

Function Get-VAMIServiceDescription
{
	
<#
.SYNOPSIS
    Get VCSA service description.
.DESCRIPTION
    This function translates VCSA service name (service-id) to its full name (description).
.EXAMPLE
    PS C:\> Get-VAMIServiceDescription -Name vsphere-ui
.EXAMPLE
	PS C:\> Get-VAMIServiceDescription vsphere-client
.NOTES
	Created by  :: Roman Gelman @rgelman75
	Version 1.0 :: 14-Jan-2019 :: [Release] :: Publicly available
.LINK
	https://ps1code.com
#>
	
	Param
	(
		[Parameter(Mandatory, Position = 0)]
		[string]$Name
	)
	
	$vcsaSvc = @{
		'vmware-vpostgres' = 'Postgres';
		'imagebuilder' = 'Image Builder Manager';
		'cm' = 'Component Manager';
		'vpxd' = 'vCenter Server';
		'sps' = 'Storage Profile-Driven Service';
		'applmgmt' = 'Appliance Management Service';
		'statsmonitor' = 'Appliance Monitoring Service';
		'rhttpproxy' = 'HTTP Reverse Proxy';
		'vapi-endpoint' = 'vAPI Endpoint';
		'vmware-stsd' = 'Security Token Service';
		'lwsmd' = 'Likewise Service Manager';
		'vmafdd' = 'Authentication Framework';
		'vmware-psc-client' = 'PSC Client';
		'vsm' = 'vService Manager';
		'vmonapi' = 'Service Lifecycle Manager API';
		'perfcharts' = 'Performance Charts';
		'updatemgr' = 'Update Manager';
		'vmware-vmon' = 'Service Lifecycle Manager';
		'vsan-health' = 'VSAN Health Service';
		'vsphere-client' = 'vSphere Web Client';
		'vmware-sts-idmd' = 'Identity Management Service';
		'vmcad' = 'Certificate Service';
		'eam' = 'ESXi Agent Manager';
		'cis-license' = 'License Service';
		'vmcam' = 'Authentication Proxy';
		'pschealth' = 'PSC Health Monitor';
		'vmdird' = 'Directory Service';
		'mbcs' = 'Message Bus Config Service';
		'vcha' = 'vCenter High Availability';
		'vsphere-ui' = 'vSphere Client';
		'content-library' = 'Content Library Service';
		'vmdnsd' = 'Domain Name Service';
		'sca' = 'Service Control Agent';
		'netdumper' = 'ESXi Dump Collector';
		'vpxd-svcs' = 'vCenter-Services';
		'rbd' = 'Auto Deploy Waiter';
	}
	
	$Description = if ($vcsaSvc.ContainsKey($Name)) { $vcsaSvc.$Name } else { '_UNKNOWN_' }
	
	[pscustomobject] @{
		Service = $Name
		Description = $Description
	}
	
} #EndFunction Get-VAMIServiceDescription

Function Get-VAMIService
{
	
<#
.SYNOPSIS
    Get VCSA services info.
.DESCRIPTION
    This function retrieves services info in VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.PARAMETER Name
	Specifies service name(s) to retrieve.
.PARAMETER State
	Specifies services current state.
.PARAMETER Startup
	Specifies services startup mode.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMIService | ogv
.EXAMPLE
	PS C:\> Get-VAMIService -State STOPPED -Startup AUTOMATIC | ft -au
	Get all UNHEALTHY services (automatic & stopped).
.EXAMPLE
    PS C:\> Get-VAMIService -Name vsphere-client
	Get service by name.
.EXAMPLE
    PS C:\> Get-VAMIService rbd, vsphere-client -Verbose
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+ | PowerShell 4.0
	Version 1.0 :: 30-Mar-2017 :: [Release] :: Publicly available
	Version 1.1 :: 18-Apr-2017 :: [Change] :: Added property 'Description'
	Version 2.0 :: 16-Jan-2019 :: [Build] :: Returned object changed to [VamiService], new parameters -State & -Startup added, the -Verbose supported
.LINK
	http://www.virtuallyghetto.com/2017/02/exploring-new-vcsa-vami-api-wpowercli-part-8.html
#>
	
	[CmdletBinding(DefaultParameterSetName = 'ALL')]
	[OutputType([VamiService])]
	Param (
		[Parameter(Position = 0, ParameterSetName = 'NAME')]
		[ValidateNotNullOrEmpty()]
		[string[]]$Name
		 ,
		[Parameter(ParameterSetName = 'ALL')]
		[ValidateSet('STARTED', 'STOPPED')]
		[string]$State
		 ,
		[Parameter(ParameterSetName = 'ALL')]
		[ValidateSet('AUTOMATIC', 'MANUAL', 'DISABLED')]
		[string]$Startup
	)
	
	$FunctionName = '{0}' -f $MyInvocation.MyCommand
	$ErrorActionPreference = 'Stop'
	foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
	{
		$serviceResult = @()
		$vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service' -Server $Server -Verbose:$false
		
		if ($PSCmdlet.ParameterSetName -eq 'NAME')
		{			
			foreach ($svc in $Name)
			{
				Try
				{
					$serviceStatus = $vMonAPI.get($svc, 0)
					$serviceString = [VamiService] @{
						Server = $Server.Name
						Name = $svc
						Description = (Get-VAMIServiceDescription $svc).Description
						State = $serviceStatus.state
						Health = ""
						Startup = $serviceStatus.startup_type
					}
					if ($serviceStatus.health -eq $null) { $serviceString.Health = "N/A" }
					else { $serviceString.Health = $serviceStatus.health }

					$serviceResult += $serviceString
				}
				Catch
				{
					Write-Verbose "$FunctionName :: The service [$svc] not found"	
				}
			}
		}
		else
		{
			$services = $vMonAPI.list_details()
			
			foreach ($key in $services.Keys | sort -Property Value)
			{
				$serviceString = [VamiService] @{
					Server = $Server.Name
					Name = $key
					Description = (Get-VAMIServiceDescription $key.Value).Description
					State = $services[$key].state
					Health = ""
					Startup = $services[$key].Startup_type
				}
				if ($services[$key].health -eq $null) { $serviceString.Health = "N/A" }
				else { $serviceString.Health = $services[$key].health }
				
				$serviceResult += $serviceString
			}
			$serviceResult = if ($PSBoundParameters.ContainsKey('State')) { $serviceResult.Where{ $_.State -eq $State } } else { $serviceResult }
			$serviceResult = if ($PSBoundParameters.ContainsKey('Startup')) { $serviceResult.Where{ $_.Startup -eq $Startup } } else { $serviceResult }
		}
		
		$serviceResult | Sort-Object Startup, State, Name
	}
	
} #EndFunction Get-VAMIService

Function Start-VAMIService
{
	
<#
.SYNOPSIS
    Start VCSA service(s).
.DESCRIPTION
    This function starts service(s) in VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMIService -Name vsphere-client | Start-VAMIService
.EXAMPLE
	PS C:\> Get-VAMIService vsan-health, vsphere-ui | Start-VAMIService -Verbose
.EXAMPLE
	PS C:\> Get-VAMIService -State STOPPED -Startup AUTOMATIC | Start-VAMIService -Confirm:$false
.NOTES
	Idea        :: William Lam @lamw
	Created by  :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+ | PowerShell 4.0
	Version 1.0 :: 30-Mar-2017 :: [Release] :: Publicly available
	Version 2.0 :: 14-Jan-2019 :: [Build] :: Gets pipeline input from the Get-VAMIService, the -Confirm parameter supported
.LINK
	http://www.virtuallyghetto.com/2017/02/exploring-new-vcsa-vami-api-wpowercli-part-8.html
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VamiService]$Service
	)
	
	Begin
	{
		$FunctionName = '{0}' -f $MyInvocation.MyCommand
	}
	Process
	{
		Try { $vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service' -Server $Service.GetServer() -Verbose:$false }
		Catch { Throw "Failed to retrieve services info from the [$($Service.GetServer())] server" }
		
		if ($Service.State -eq 'STOPPED')
		{
			if ($PSCmdlet.ShouldProcess("VCSA [$($Service.GetServer())]", "Start [$((Get-VAMIServiceDescription $Service).Description)] service"))
			{
				Try
				{
					Write-Verbose "$FunctionName :: Starting [$Service] service ..."
					$vMonAPI.start($Service)
					Write-Verbose "$FunctionName :: Service [$Service] started successfully"
					
				}
				Catch
				{
					Write-Verbose "$FunctionName :: Failed to start [$Service] service ..."
				}
				(Get-VAMIService $Service).Where{ $_.Server -eq $Service.GetServer() }
			}
		}
		else
		{
			Write-Verbose "$FunctionName :: The service [$Service] is skipped because it's already started"
		}
	}
	
	End { }
	
} #EndFunction Start-VAMIService

Function Stop-VAMIService
{
	
<#
.SYNOPSIS
    Stop VCSA service(s).
.DESCRIPTION
    This function stops service(s) in VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMIService -Name vsphere-client | Stop-VAMIService
.EXAMPLE
	PS C:\> Get-VAMIService vsan-health, vsphere-ui | Stop-VAMIService -Confirm:$false -Verbose
.NOTES
	Idea        :: William Lam @lamw
	Created by  :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+ | PowerShell 4.0
	Version 1.0 :: 30-Mar-2017 :: [Release] :: Publicly available
	Version 2.0 :: 14-Jan-2019 :: [Build] :: Gets pipeline input from the Get-VAMIService, the -Confirm parameter supported
.LINK
	http://www.virtuallyghetto.com/2017/02/exploring-new-vcsa-vami-api-wpowercli-part-8.html
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VamiService]$Service
	)
	
	Begin
	{
		$FunctionName = '{0}' -f $MyInvocation.MyCommand
	}
	Process
	{
		Try { $vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service' -Server $Service.GetServer() -Verbose:$false }
		Catch { Throw "Failed to retrieve services info from the [$($Service.GetServer())] server" }
		
		if ($Service.State -eq 'STARTED')
		{
			if ($PSCmdlet.ShouldProcess("VCSA [$($Service.GetServer())]", "Stop [$((Get-VAMIServiceDescription $Service).Description)] service"))
			{
				Try
				{
					Write-Verbose "$FunctionName :: Stopping [$Service] service ..."
					$vMonAPI.stop($Service)
					Write-Verbose "$FunctionName :: Service [$Service] stopped successfully"
					
				}
				Catch
				{
					Write-Verbose "$FunctionName :: Failed to stop [$Service] service ..."
				}
				(Get-VAMIService $Service).Where{ $_.Server -eq $Service.GetServer() }
			}
		}
		else
		{
			Write-Verbose "$FunctionName :: The service [$Service] is skipped because it's already stopped"
		}
	}
	
	End { }
	
} #EndFunction Stop-VAMIService

Function Restart-VAMIService
{
	
<#
.SYNOPSIS
    Restart VCSA service(s).
.DESCRIPTION
    This function restarts service(s) in VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMIService -Name vsphere-client | Restart-VAMIService
.EXAMPLE
	PS C:\> Get-VAMIService vsan-health, vsphere-ui | Restart-VAMIService -Confirm:$false -Verbose
.NOTES
	Idea        :: William Lam @lamw
	Created by  :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+ | PowerShell 4.0
	Version 1.0 :: 30-Mar-2017 :: [Release] :: Publicly available
	Version 2.0 :: 14-Jan-2019 :: [Build] :: Gets pipeline input from the Get-VAMIService, the -Confirm parameter supported
.LINK
	http://www.virtuallyghetto.com/2017/02/exploring-new-vcsa-vami-api-wpowercli-part-8.html
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VamiService]$Service
	)
	
	Begin
	{
		$FunctionName = '{0}' -f $MyInvocation.MyCommand
	}
	Process
	{
		Try { $vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service' -Server $Service.GetServer() -Verbose:$false }
		Catch { Throw "Failed to retrieve services info from the [$($Service.GetServer())] server" }
		
		if ($Service.State -eq 'STARTED')
		{
			if ($PSCmdlet.ShouldProcess("VCSA [$($Service.GetServer())]", "Restart [$((Get-VAMIServiceDescription $Service).Description)] service"))
			{
				Try
				{
					Write-Verbose "$FunctionName :: Restarting [$Service] service ..."
					$vMonAPI.restart($Service)
					Write-Verbose "$FunctionName :: Service [$Service] restarted successfully"
					
				}
				Catch
				{
					Write-Verbose "$FunctionName :: Failed to restart [$Service] service ..."
				}
				(Get-VAMIService $Service).Where{ $_.Server -eq $Service.GetServer() }
			}
		}
		else
		{
			Write-Verbose "$FunctionName :: The service [$Service] is skipped because it's not started"	
		}
	}
	
	End { }
	
} #EndFunction Restart-VAMIService

Function Get-VAMIBackupSize
{
	
<#
.SYNOPSIS
	This function retrieves the backup size of the VCSA from VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
	Function to return the current backup size of the VCSA (common and core data).
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMIBackupSize
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 30-Mar-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/03/exploring-new-vcsa-vami-api-wpowercli-part-9.html
#>
	
	$ErrorActionPreference = 'Stop'
	foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
	{
		Try
		{
			$recoveryAPI = Get-CisService 'com.vmware.appliance.recovery.backup.parts' -Server $Server
			$backupParts = $recoveryAPI.list() | select id, description
			
			$estimateBackupSize = 0
			
			foreach ($backupPart in $backupParts)
			{
				$partId = $backupPart.id.value
				$partSize = $recoveryAPI.get($partId)
				$partIdName = if ($partId -eq 'seat') { $partId.ToUpper() }
				else { (Get-Culture).TextInfo.ToTitleCase($partId) }
				
				$estimateBackupSize += $partSize
				
				$recoveryResult = [pscustomobject] @{
					Server = $Server.Name
					BackupPart = $partIdName
					Description = $backupPart.description.default_message -replace '\.$', $null
					SizeMB = $partSize
				}
				$recoveryResult
			}
			
			$estimateResult = [pscustomobject] @{
				Server = $Server.Name
				BackupPart = 'Total'
				Description = 'Total estimated backup size'
				SizeMB = $estimateBackupSize
			}
			$estimateResult
		}
		Catch { }
	}
	
} #EndFunction Get-VAMIBackupSize

Function Get-VAMIUser
{
	
<#
.SYNOPSIS
	This function retrieves VAMI local users using VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
	Function to retrieve VAMI local users.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMIUser root
.EXAMPLE
	PS C:\> Get-VAMIUser |Format-Table -AutoSize
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 30-Mar-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/03/exploring-new-vcsa-vami-api-wpowercli-part-10.html
#>
	
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullOrEmpty()]
		[string[]]$Name
	)
	
	$ErrorActionPreference = 'Stop'
	foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
	{
		$userResults = @()
		$userAPI = Get-CisService 'com.vmware.appliance.techpreview.localaccounts.user' -Server $Server
		
		If ($PSBoundParameters.ContainsKey('Name'))
		{
			foreach ($account in $Name)
			{
				Try
				{
					$user = $userAPI.get($account)
					
					$userString = [pscustomobject] @{
						Server = $Server.Name
						User = $user.username
						Name = $user.fullname
						Email = $user.email
						Status = $user.status
						PasswordStatus = $user.passwordstatus
						Role = $user.role
					}
					$userResults += $userString
				}
				Catch { }
			}
		}
		Else
		{
			$users = $userAPI.list()
			
			foreach ($user in $users)
			{
				$userString = [pscustomobject] @{
					Server = $Server.Name
					User = $user.username
					Name = $user.fullname
					Email = $user.email
					Status = $user.status
					PasswordStatus = $user.passwordstatus
					Role = $user.role
				}
				$userResults += $userString
			}
		}
	}
	$userResults
	
} #EndFunction Get-VAMIUser

Function New-VAMIUser
{
	
<#
.SYNOPSIS
	This function to create new VAMI local user using VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
	Function to create a new VAMI local user.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> New-VAMIUser lamw "William Lam" "VMware1!" -Role "operator" -Email "lamw@virtuallyghetto.com" -Verbose
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 30-Mar-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/03/exploring-new-vcsa-vami-api-wpowercli-part-10.html
#>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory,Position=0)]
		[string]$Name
		 ,
		[Parameter(Mandatory,Position=1)]
		[string]$Fullname
		 ,
		[Parameter(Mandatory = $false)]
		[ValidateSet("admin", "operator", "superAdmin")]
		[string]$Role = "superAdmin"
		 ,
		[Parameter(Mandatory = $false)]
		[string]$Email = ""
		 ,
		[Parameter(Mandatory,Position=2)]
		[string]$Password
	)
	
	Begin { }
	
	Process
	{
		foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
		{
			$userAPI = Get-CisService 'com.vmware.appliance.techpreview.localaccounts.user' -Server $Server -Verbose:$false
			$createSpec = $userAPI.Help.add.config.CreateExample()
			
			$createSpec.username = $Name
			$createSpec.fullname = $Fullname
			$createSpec.role = $Role
			$createSpec.email = $Email
			$createSpec.password = [VMware.VimAutomation.Cis.Core.Types.V1.Secret]$Password
			
			Try
			{
				Write-Verbose "Creating new user [$Name] on server [$($Server.Name)] ..."
				$userAPI.add($createSpec)
				Write-Verbose "New user [$Name] created successfully on server [$($Server.Name)]"
				
				If (!$PSBoundParameters.ContainsKey('Verbose')) { Get-VAMIUser $Name }
			}
			Catch
			{
				Write-Verbose "Failed to create [$Name] user on server [$($Server.Name)]"
			}
		}
	}
	
	End { }
	
} #EndFunction New-VAMIUser

Function Remove-VAMIUser
{
	
<#
.SYNOPSIS
	This function to remove VAMI local user using VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
	Function to remove VAMI local user.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Remove-VAMIUser lamw
.EXAMPLE
    PS C:\> Remove-VAMIUser lamw -Verbose -Confirm:$false
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 30-Mar-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/03/exploring-new-vcsa-vami-api-wpowercli-part-10.html
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	Param (
		[Parameter(Mandatory)]
		[string]$Name
	)
	
	Begin
	{
		If ($Name -eq 'root') {Throw "There is no possible to delete [root] account!"}	
	}
	
	Process
	{
		foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
		{
			If ($PSCmdlet.ShouldProcess("VAMI Server [$($Server.Name)]", "Delete local user [$Name]?"))
			{
				$userAPI = Get-CisService 'com.vmware.appliance.techpreview.localaccounts.user' -Server $Server -Verbose:$false
				
				Try
				{
					$userAPI.delete($Name)
					Write-Verbose "Local user account [$Name] deleted successfully from server [$($Server.Name)]"
				}
				Catch
				{
					Write-Verbose "Failed to delete local user account [$Name] from server [$($Server.Name)]"
				}
			}
		}
	}
	
} #EndFunction Remove-VAMIUser

Function Suspend-VAMIShutdown
{
	
<#
.SYNOPSIS
    Cancel pending VMware Appliance reboot/shutdown.
.DESCRIPTION
    This function cancels a pending reboot or shutdown for any connected VMware Appliance(s).
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Suspend-VAMIShutdown
.EXAMPLE
	PS C:\> Suspend-VAMIShutdown -Verbose
.EXAMPLE
	PS C:\> Suspend-VAMIShutdown -Confirm:$false
	Silently cancel a pending shutdown in all connected appliances.
.NOTES
	Author      :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 15-Jan-2019 :: [Release] :: Publicly available
.LINK
	https://code.vmware.com/apis/60/vcenter-server-appliance-management
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	[Alias('Cancel-VAMIShutdown', 'Cancel-VAMIRestart')]
	Param ()
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$FunctionName = '{0}' -f $MyInvocation.MyCommand
	}
	Process
	{
		foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
		{
			$ShutdownAPI = Get-CisService -Name "com.vmware.appliance.techpreview.shutdown" -Server $Server -Verbose:$false
			$Schedule = $ShutdownAPI.get()
			
			if ($Schedule.shutdown_time)
			{
				if ($PSCmdlet.ShouldProcess("VMware Appliance [$($Server.Name)]", "Cancel pending $($Schedule.action) scheduled to $($Schedule.shutdown_time)"))
				{
					Try
					{
						$ShutdownAPI.cancel()
						Write-Verbose "$FunctionName :: Pending $($Schedule.action) successfully canceled on the [$($Server.Name)] VMware Appliance"
					}
					Catch { Write-Verbose "$FunctionName :: Failed to cancel $($Schedule.action) on [$($Server.Name)] VMware Appliance" }
				}
			}
			else
			{
				Write-Verbose "$FunctionName :: The VMware Appliance [$($Server.Name)] is not scheduled for reboot or shutdown"
			}
		}
	}
	End { }
	
} #EndFunction Suspend-VAMIShutdown

Function Stop-VAMIAppliance
{
	
<#
.SYNOPSIS
    Shutdown/Reboot VMware Appliance.
.DESCRIPTION
    This function schedules shutdown or reboot for any connected VMware Appliance(s).
.PARAMETER Reason
	Specifies reason for what reboot or shutdown was made.
.PARAMETER Delay
	Specifies delay for the scheduled shutdown/reboot in MINUTES.
	The minimum allowed by API is one minute.
	The maximum allowed by function is one week.
.PARAMETER Wait
	If specified, the function will wait for the action to complete,
	otherwise the action will be scheduled and the function exits.
.PARAMETER Reboot
	If specified, the reboot is scheduled, otherwise the action is shutdown.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Stop-VAMIAppliance
	Shutdown connected appliance(s).
.EXAMPLE
	PS C:\> Stop-VAMIAppliance xyu 20 -Verbose -Wait
	Schedule shutdown and wait for complete.
.EXAMPLE
	PS C:\> Stop-VAMIAppliance -Confirm:$false -Reboot
	Silently restart all connected appliances using default delay and reason.
.NOTES
	Author      :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+ | VCSA 6.5+
	Version 1.0 :: 15-Jan-2019 :: [Release] :: Publicly available
.LINK
	https://code.vmware.com/apis/60/vcenter-server-appliance-management
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	[Alias('Shutdown-VAMIAppliance', 'Restart-VAMIAppliance')]
	Param (
		[Parameter(Position = 0)]
		[string]$Reason
		 ,
		[Parameter(Position = 1)]
		[ValidateRange(1, 10080)]
		[uint16]$Delay = 1
		 ,
		[switch]$Wait
		 ,
		[switch]$Reboot
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$FunctionName = '{0}' -f $MyInvocation.MyCommand
		$CmdAPI = @{ }
		if ($Reboot) { $CmdAPI.api = 'reboot'; $CmdAPI.action = 'reboot'; $CmdAPI.Capital = 'Reboot' }
		else { $CmdAPI.api = 'poweroff'; $CmdAPI.action = 'shutdown'; $CmdAPI.Capital = 'Shutdown'; }
	}
	Process
	{
		foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
		{
			$Reason = if (!$Reason) { $Server.User } else { $Reason }
			
			if ($PSCmdlet.ShouldProcess("VMware Appliance [$($Server.Name)]", "$($CmdAPI.Capital) for the [$Reason] reason"))
			{
				Try
				{
					$ShutdownAPI = Get-CisService -Name "com.vmware.appliance.techpreview.shutdown" -Server $Server -Verbose:$false
					
					$ShutdownConfig = $ShutdownAPI.Help.$($CmdAPI.api).config.Create()
					$ShutdownConfig.delay = $Delay
					$ShutdownConfig.reason = $Reason
					
					$ShutdownAPI.$($CmdAPI.api)($ShutdownConfig)
					
					Write-Verbose "$FunctionName :: The VMware Appliance [$($Server.Name)] scheduled for the $($CmdAPI.action)"
					
					$Schedule = $ShutdownAPI.get()
					[pscustomobject] @{
						Server = $Server.Name
						Action = (Get-Culture -Verbose:$false).TextInfo.ToTitleCase($Schedule.action)
						Reason = $Schedule.reason
						Invoked = Get-Date -Verbose:$false -Format 'yyyy-MM-dd HH:mm:ss'
						Scheduled = $Schedule.shutdown_time
					}
					
					if ($Wait)
					{
						$TotalSec = [Math]::Round((New-TimeSpan -Start (Get-Date) -End (Get-Date $Schedule.shutdown_time) -Verbose:$false).TotalSeconds, 0)
						for ($i = 0; $i -lt $TotalSec; $i++)
						{
							Write-Progress -Activity "$FunctionName :: VMware Appliance [$($Server.Name)]" `
										   -Status "Elapsed $i seconds" `
										   -CurrentOperation "Left $($TotalSec - $i) seconds before $($CmdAPI.action)" `
										   -PercentComplete ([Math]::Round($i/$TotalSec * 100, 0))
							Start-Sleep -Milliseconds 980
						}
					}
				}
				Catch { Write-Verbose "$FunctionName :: Failed to $($CmdAPI.action) the [$($Server.Name)] VMware Appliance" }
			}
		}
	}
	End { }
	
} #EndFunction Stop-VAMIAppliance
