Function Get-VAMISummary
{
	
<#
.SYNOPSIS
    This function retrieves some basic information from VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
    Function to return basic VAMI summary info.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMISummary
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
	Version 1.0 :: 29-Mar-2017 :: [Release] :: Publicly available
	Version 1.1 :: 07-Dec-2017 :: [Feature] :: New properties added: Release, ReleaseDate, BackupExpireDate, DaysToExpire
.LINK
	https://ps1code.com/2017/12/10/vcsa-backup-expiration-powercli
#>
	$ErrorActionPreference = 'Stop'
	
	foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
	{
		Try
		{
			$SystemVersionAPI = Get-CisService -Name 'com.vmware.appliance.system.version' -Server $Server
			$results = $SystemVersionAPI.get() | select product, 'type', version, build, install_time
			
			$Expiration = switch -exact ($results.build)
			{
				'4602587' { '10/22/2017'; $Release = '6.5.0GA'; $ReleaseDate = '11/15/2016' }
				'4944578' { '10/22/2017'; $Release = '6.5.0a'; $ReleaseDate = '02/02/2017' }
				'5178943' { '02/03/2018'; $Release = '6.5.0b'; $ReleaseDate = '03/14/2017' }
				'5318112' { '02/03/2018'; $Release = '6.5.0c'; $ReleaseDate = '04/13/2017' }
				'5318154' { '02/03/2018'; $Release = '6.5.0d'; $ReleaseDate = '04/18/2017' }
				'5705665' { '02/03/2018'; $Release = '6.5.0e'; $ReleaseDate = '06/15/2017' }
				'5973321' { '07/01/2018'; $Release = '6.5.0U1'; $ReleaseDate = '07/27/2017' }
				'6671409' { '08/14/2018'; $Release = '6.5.0U1a'; $ReleaseDate = '09/21/2017' }
				'6816762' { '09/26/2018'; $Release = '6.5.0U1b'; $ReleaseDate = '10/26/2017' }
				'7119070' { '10/01/2018'; $Release = '6.5.0f'; $ReleaseDate = '11/14/2017' }
				'7119157' { '10/01/2018'; $Release = '6.5.0U1c'; $ReleaseDate = '11/14/2017'}
			}
			
			$SystemUptimeAPI = Get-CisService -Name 'com.vmware.appliance.system.uptime' -Server $Server
			$ts = [timespan]::FromSeconds($SystemUptimeAPI.get().ToString())
			$uptime = $ts.ToString("dd\ \D\a\y\s\,\ hh\:mm\:ss")
			
			$SummaryResult = [pscustomobject] @{
				Server = $Server.Name
				Product = $results.product
				Type = $results.type
				Version = [version]$results.version
				Build = [uint32]$results.build
				Release = $Release
				ReleaseDate = Get-Date $ReleaseDate -Format "MM/dd/yyyy"
				InstallDate = ([datetime]($results.install_time -replace '[a-zA-Z]', ' ')).ToLocalTime()
				BackupExpireDate = Get-Date $Expiration -Format "MM/dd/yyyy"
				DaysToExpire = [System.Math]::Round((New-TimeSpan -End $Expiration -Start (Get-Date)).TotalDays, 0)
				Uptime = $uptime
			}
			$SummaryResult
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
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
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
    This function retrieves access information from VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
    Function to return VAMI access interfaces (Console,DCUI,Bash Shell & SSH).
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMIAccess
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
	Version 1.0 :: 29-Mar-2017 :: [Release] :: Publicly available
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
			
			$accessResult = [pscustomobject] @{
				Server = $Server.Name
				Console = $consoleAccess
				DCUI = $dcuiAccess
				BashShell = $shellAccess.enabled
				SSH = $sshAccess
			}
			$accessResult	
		}
		Catch { }
	}
	
} #EndFunction Get-VAMIAccess

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
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
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
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
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
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
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
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
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
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
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
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
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
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
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

Function Get-VAMIService
{
	
<#
.SYNOPSIS
    This function retrieves list of services in VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
    Function to return list of services and their description.
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Get-VAMIService |ft -au
.EXAMPLE
	PS C:\> Get-VAMIService |? {$_.Startup -eq 'AUTOMATIC' -and $_.Health -ne 'HEALTHY'}
	Get all Unhealthy automatic services.
.EXAMPLE
    PS C:\> Get-VAMIService -Name rbd
.EXAMPLE
    PS C:\> Get-VAMIService rbd,vsphere-client
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
	Version 1.0 :: 30-Mar-2017 :: [Release] :: Publicly available
	Version 1.1 :: 18-Apr-2017 :: [Change] :: Added property `Description`
.LINK
	http://www.virtuallyghetto.com/2017/02/exploring-new-vcsa-vami-api-wpowercli-part-8.html
#>
	
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullOrEmpty()]
		[string[]]$Name
	)
	
	$vcsaSvc = @{
		'vmware-vpostgres' = 'VMware Postgres';
		'imagebuilder' = 'VMware Image Builder Manager';
		'cm' = 'VMware Component Manager';
		'vpxd' = 'VMware vCenter Server';
		'sps' = 'VMware vSphere Profile-Driven Storage Service';
		'applmgmt' = 'VMware Appliance Management Service';
		'statsmonitor' = 'VMware Appliance Monitoring Service';
		'rhttpproxy' = 'VMware HTTP Reverse Proxy';
		'vapi-endpoint' = 'VMware vAPI Endpoint';
		'vmware-stsd' = 'VMware Security Token Service';
		'lwsmd' = 'Likewise Service Manager';
		'vmafdd' = 'VMware Authentication Framework';
		'vmware-psc-client' = 'VMware Platform Services Controller Client';
		'vsm' = 'VMware vService Manager';
		'vmonapi' = 'VMware Service Lifecycle Manager API';
		'perfcharts' = 'VMware Performance Charts';
		'updatemgr' = 'VMware Update Manager';
		'vmware-vmon' = 'VMware Service Lifecycle Manager';
		'vsan-health' = 'VMware VSAN Health Service';
		'vsphere-client' = 'VMware vSphere Web Client';
		'vmware-sts-idmd' = 'VMware Identity Management Service';
		'vmcad' = 'VMware Certificate Service';
		'eam' = 'VMware ESX Agent Manager';
		'cis-license' = 'VMware License Service';
		'vmcam' = 'VMware vSphere Authentication Proxy';
		'pschealth' = 'VMware Platform Services Controller Health Monitor';
		'vmdird' = 'VMware Directory Service';
		'mbcs' = 'VMware Message Bus Configuration Service';
		'vcha' = 'VMware vCenter High Availability';
		'vsphere-ui' = 'VMware vSphere Client';
		'content-library' = 'VMware Content Library Service';
		'vmdnsd' = 'VMware Domain Name Service';
		'sca' = 'VMware Service Control Agent';
		'netdumper' = 'VMware vSphere ESXi Dump Collector';
		'vpxd-svcs' = 'VMware vCenter-Services';
		'rbd' = 'VMware vSphere Auto Deploy Waiter';
	}
	
	$ErrorActionPreference = 'Stop'
	foreach ($Server in ($global:DefaultCisServers | ? { $_.IsConnected }))
	{
		$serviceResult = @()
		$vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service' -Server $Server
		
		If ($PSBoundParameters.ContainsKey('Name'))
		{			
			foreach ($svc in $Name)
			{
				Try
				{
					$serviceStatus = $vMonAPI.get($svc, 0)
					$serviceString = [pscustomobject] @{
						Server = $Server.Name
						Name = $svc
						Description = $vcsaSvc[$svc]
						State = $serviceStatus.state
						Health = ""
						Startup = $serviceStatus.startup_type
					}
					if ($serviceStatus.health -eq $null) { $serviceString.Health = "N/A" }
					else { $serviceString.Health = $serviceStatus.health }

					$serviceResult += $serviceString
				}
				Catch { }
			}
		}
		Else
		{
			$services = $vMonAPI.list_details()
			
			foreach ($key in $services.Keys | sort -Property Value)
			{
				$serviceString = [pscustomobject] @{
					Server = $Server.Name
					Name = $key
					Description = $vcsaSvc[$key.Value]
					State = $services[$key].state
					Health = ""
					Startup = $services[$key].Startup_type
				}
				if ($services[$key].health -eq $null) { $serviceString.Health = "N/A" }
				else { $serviceString.Health = $services[$key].health }
				
				$serviceResult += $serviceString
			}
		}
		$serviceResult
	}
	
} #EndFunction Get-VAMIService

Function Start-VAMIService
{
	
<#
.SYNOPSIS
    This function starts service(s) in VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
    Function to start VCSA service(s).
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Start-VAMIService -Name rbd
.EXAMPLE
	PS C:\> Get-VAMIService rbd,vsphere-client |Start-VAMIService -Verbose
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
	Version 1.0 :: 30-Mar-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/02/exploring-new-vcsa-vami-api-wpowercli-part-8.html
#>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[string]$Name
		 ,
		[Parameter(Mandatory, ValueFromPipelineByPropertyName)]
		[string]$Server
	)
	
	Begin { }
	
	Process
	{
		$CisServer = $global:DefaultCisServers | ? { $_.Name -eq $Server -and $_.IsConnected }
		Try { $vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service' -Server $CisServer -Verbose:$false }
		Catch { Throw "Failed to retrieve services info from [$Server] server" }
		
		Try
		{
			Write-Verbose "Starting [$Name] service ..."
			$vMonAPI.start($Name)
			Write-Verbose "Service [$Name] started successfully"
			
			If (!$PSBoundParameters.ContainsKey('Verbose')) { Get-VAMIService $Name }
		}
		Catch
		{
			Write-Verbose "Failed to start [$Name] service"
		}
	}
	
	End { }
	
} #EndFunction Start-VAMIService

Function Stop-VAMIService
{
	
<#
.SYNOPSIS
    This function stops service(s) in VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
    Function to stop VCSA service(s).
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Stop-VAMIService -Name rbd
.EXAMPLE
	PS C:\> Get-VAMIService rbd,vsphere-client |Stop-VAMIService -Verbose
.NOTES
	Created by  :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
	Version 1.0 :: 30-Mar-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/02/exploring-new-vcsa-vami-api-wpowercli-part-8.html
#>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[string]$Name
		 ,
		[Parameter(Mandatory, ValueFromPipelineByPropertyName)]
		[string]$Server
	)
	
	Begin { }
	
	Process
	{
		$CisServer = $global:DefaultCisServers | ? { $_.Name -eq $Server -and $_.IsConnected }
		Try { $vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service' -Server $CisServer -Verbose:$false }
		Catch { Throw "Failed to retrieve services info from [$Server] server" }
		
		Try
		{
			Write-Verbose "Stoping [$Name] service ..."
			$vMonAPI.stop($Name)
			Write-Verbose "Service [$Name] stoped successfully"
			
			If (!$PSBoundParameters.ContainsKey('Verbose')) { Get-VAMIService $Name }
		}
		Catch
		{
			Write-Verbose "Failed to stop [$Name] service ..."
		}
	}
	
	End { }
	
} #EndFunction Stop-VAMIService

Function Restart-VAMIService
{
	
<#
.SYNOPSIS
    This function restarts service(s) in VAMI interface (5480)
    for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
.DESCRIPTION
    Function to restart VCSA service(s).
.EXAMPLE
    PS C:\> Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
    PS C:\> Restart-VAMIService -Name rbd
.EXAMPLE
	PS C:\> Get-VAMIService rbd,vsphere-client |Restart-VAMIService -Verbose
.NOTES
	Idea        :: William Lam @lamw
	Created by  :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
	Version 1.0 :: 30-Mar-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/02/exploring-new-vcsa-vami-api-wpowercli-part-8.html
#>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[string]$Name
		 ,
		[Parameter(Mandatory, ValueFromPipelineByPropertyName)]
		[string]$Server
	)
	
	Begin { }
	
	Process
	{
		$CisServer = $global:DefaultCisServers | ? { $_.Name -eq $Server -and $_.IsConnected }
		Try { $vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service' -Server $CisServer -Verbose:$false }
		Catch { Throw "Failed to retrieve services info from [$Server] server" }
		
		Try
		{
			Write-Verbose "Restarting [$Name] service ..."
			$vMonAPI.restart($Name)
			Write-Verbose "Service [$Name] restarted successfully"
			
			If (!$PSBoundParameters.ContainsKey('Verbose')) { Get-VAMIService $Name }
		}
		Catch
		{
			Write-Verbose "Failed to restart [$Name] service ..."
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
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
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
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
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
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
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
	Requirement :: PowerCLI 6.5+, VCSA 6.5+
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
