Class ViModule { } #EndClass ViModule

Class ViSession: ViModule
{
	[ValidateNotNullOrEmpty()][string]$VC
	[ValidateNotNullOrEmpty()][string]$Key
	[ValidateNotNullOrEmpty()][string]$UserName
	[string]$FullName
	[ValidateNotNullOrEmpty()][string]$Client
	[ValidateNotNullOrEmpty()][string]$ClientType
	[ValidateNotNullOrEmpty()][datetime]$LoginTime
	[ValidateNotNullOrEmpty()][datetime]$LastActiveTime
	[ValidateSet('_THIS_', 'Foreign')][string]$Session
	[double]$IdleMinutes
} #EndClass ViSession

Class ViCDP: ViModule
{
	[ValidateNotNullOrEmpty()][string]$VMHost
	[ValidateNotNullOrEmpty()][string]$NIC
	[ValidateNotNullOrEmpty()][string]$MAC
	[ValidateNotNullOrEmpty()][string]$Vendor
	[ValidateNotNullOrEmpty()][string]$Driver
	[bool]$CDP
	[int]$LinkMbps
	[string]$Switch
	[string]$Hardware
	[string]$Software
	[ipaddress]$MgmtIP
	[string]$MgmtVlan
	[string]$PortId
	[string]$Vlan
	
	[string] ToString () { return "$($this.VMHost)::$($this.NIC) -> $($this.Switch)::$($this.PortId)" }
	
	[pscustomobject[]] GetAllVlan ()
	{
		return $this.Vlan -split ', ' | % { [pscustomobject] @{ VMHost = $this.VMHost; NIC = $this.NIC; Switch = $this.Switch; Port = $this.PortId; Vlan = $_ -as [int] } }
	}
	
	[pscustomobject[]] GetVlan ([int[]]$VlanId)
	{
		return $this.Vlan -split ', ' | % { if ($VlanId -contains $_) { [pscustomobject] @{ VMHost = $this.VMHost; NIC = $this.NIC; Switch = $this.Switch; Port = $this.PortId; Vlan = $_ -as [int] } } }
	}
	
} #EndClass ViCDP

Function Get-RDM
{
	
<#
.SYNOPSIS
	Get all RDMs.
.DESCRIPTION
	This function reports all VMs with their RDM disks.
.PARAMETER VM
	VM's collection, returned by Get-VM cmdlet.
.EXAMPLE
	C:\PS> Get-VM -Server VC1 |Get-RDM
.EXAMPLE
	C:\PS> Get-VM |? {$_.Name -like 'linux*'} |Get-RDM |sort VM,Datastore,HDLabel |ft -au
.EXAMPLE
	C:\PS> Get-Datacenter 'North' |Get-VM |Get-RDM |? {$_.HDSizeGB -gt 1} |Export-Csv -NoTypeInformation 'C:\reports\North_RDMs.csv'
.EXAMPLE
	C:\PS> $res = Get-Cluster prod |Get-VM |Get-ViMRDM
	C:\PS> $res |Export-Csv -NoTypeInformation 'C:\reports\ProdCluster_RDMs.csv'
	Save the results in variable and than export them to a file.
.INPUTS
	[VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]] Get-VM collection.
.OUTPUTS
	[System.Management.Automation.PSCustomObject] PSObject collection.
.NOTES
	Author: Roman Gelman @rgelman75
	Version 1.0 :: 16-Oct-2015 :: [Release] :: Publicly available
	Version 1.1 :: 03-Dec-2015 :: [Bugfix]  :: Error message appear while VML mismatch, when the VML identifier does not match for an RDM on two or more ESXi hosts. VMware [KB2097287].
	Version 1.2 :: 03-Aug-2016 :: [Improvement] :: GetType() method replaced by -is to determine data type
.LINK
	https://ps1code.com/2015/10/16/get-rdm-disks-powercli
#>
	
	[CmdletBinding()]
	[Alias("Get-ViMRDM")]
	Param (
		
		[Parameter(Mandatory = $false, Position = 1, ValueFromPipeline = $true, HelpMessage = "VM's collection, returned by Get-VM cmdlet")]
		[ValidateNotNullorEmpty()]
		[Alias("VM")]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$VMs = (Get-VM)
		
	)
	
	Begin
	{
		
		$Object = @()
		$regxVMDK = '^\[(?<Datastore>.+)\]\s(?<Filename>.+)$'
		$regxLUNID = ':L(?<LUNID>\d+)$'
	}
	
	Process
	{
		
		Foreach ($vm in ($VMs | Get-View))
		{
			Foreach ($dev in $vm.Config.Hardware.Device)
			{
				If ($dev -is [VMware.Vim.VirtualDisk])
				{
					If ("physicalMode", "virtualMode" -contains $dev.Backing.CompatibilityMode)
					{
						
						Write-Progress -Activity "Gathering RDM ..." -CurrentOperation "Hard disk - [$($dev.DeviceInfo.Label)]" -Status "VM - $($vm.Name)"
						
						$esx = Get-View $vm.Runtime.Host
						$esxScsiLun = $esx.Config.StorageDevice.ScsiLun | ? { $_.Uuid -eq $dev.Backing.LunUuid }
						
						### Expand 'LUNID' from device runtime name (vmhba2:C0:T0:L12) ###
						$lunCN = $esxScsiLun.CanonicalName
						$Matches = $null
						If ($lunCN)
						{
							$null = (Get-ScsiLun -VmHost $esx.Name -CanonicalName $lunCN -ErrorAction SilentlyContinue).RuntimeName -match $regxLUNID
							$lunID = $Matches.LUNID
						}
						Else { $lunID = '' }
						
						### Expand 'Datastore' and 'VMDK' from file path ###
						$null = $dev.Backing.FileName -match $regxVMDK
						
						$Properties = [ordered]@{
							VM = $vm.Name
							VMHost = $esx.Name
							Datastore = $Matches.Datastore
							VMDK = $Matches.Filename
							HDLabel = $dev.DeviceInfo.Label
							HDSizeGB = [math]::Round(($dev.CapacityInKB / 1MB), 3)
							HDMode = $dev.Backing.CompatibilityMode
							DeviceName = $dev.Backing.DeviceName
							Vendor = $esxScsiLun.Vendor
							CanonicalName = $lunCN
							LUNID = $lunID
						}
						$Object = New-Object PSObject -Property $Properties
						$Object
					}
				}
			}
		}
	}
	
	End
	{
		Write-Progress -Completed $true -Status "Please wait"
	}
	
} #EndFunction Get-RDM

Function Convert-VmdkThin2EZThick
{
	
<#
.SYNOPSIS
	Inflate Thin Provision virtual disks.
.DESCRIPTION
	The Convert-VmdkThin2EZThick function converts Thin Provision VM disk(s) to the type 'Thick Provision Eager Zeroed'.
	Thick disks or disks with snapshots are skipped by the function.
.PARAMETER VM
	Object(s), returned by `Get-VM` cmdlet.
.EXAMPLE
	PS C:\> Get-VM VM1 |Convert-VmdkThin2EZThick
.EXAMPLE
	PS C:\> Get-VM VM1,VM2 |Convert-VmdkThin2EZThick -Confirm:$false |sort VM,Datastore,VMDK |ft -au
.EXAMPLE
	PS C:\> Get-VM 'vm[1-5]' |thin2thick -Verbose
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0|PowerCLi 6.5
	Platform    :: Tested on vSphere 5.5/6.0|VCenter 5.5U2/VCSA 6.0U1
	Requirement :: PowerShell 3.0+, VM must be PoweredOff
	Version 1.0 :: 05-Nov-2015 :: [Release] :: Publicly available
	Version 1.1 :: 03-Aug-2016 :: [Change]  :: Parameter `-VMs` renamed to `-VM`
	Version 1.2 :: 18-Jan-2017 :: [Change]  :: Cofirmation asked on per-disk basis instead of per-VM, added `Write-Warning` and `Write-Verbose` messages, minor code changes
.LINK
	https://ps1code.com/2015/11/05/convert-vmdk-thin2thick-powercli
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess = $true)]
	[Alias("Convert-ViMVmdkThin2EZThick", "thin2thick")]
	[OutputType([PSCustomObject])]
	Param (
		[Parameter(Mandatory, Position = 0, ValueFromPipeline)]
		[Alias("VMs")]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$VM
	)
	
	Begin
	{
		$Object = @()
		$regxVMDK = '^\[(?<Datastore>.+)\]\s(?<Filename>.+)$'
	} #EndBegin
	
	Process
	{
		
		Foreach ($vmv in ($VM | Get-View -Verbose:$false))
		{
			
			### Validate VM prerequisites ###
			If ($vmv.Runtime.PowerState -eq 'poweredOff')
			{
				
				### Get ESXi object where $vmv is registered ###
				$esx = Get-View $vmv.Runtime.Host -Verbose:$false
				
				### Get Datacenter object where $vmv is registered ###
				$parentObj = Get-View $vmv.Parent -Verbose:$false
				While ($parentObj -isnot [VMware.Vim.Datacenter]) { $parentObj = Get-View $parentObj.Parent -Verbose:$false }
				$datacenter = New-Object VMware.Vim.ManagedObjectReference
				$datacenter.Type = 'Datacenter'
				$datacenter.Value = $parentObj.MoRef.Value
				
				Foreach ($dev in $vmv.Config.Hardware.Device)
				{
					If ($dev -is [VMware.Vim.VirtualDisk])
					{
						
						$sizeGB = [Math]::Round(($dev.CapacityInKB / 1MB), 1)
						If ($dev.Backing.ThinProvisioned -and !($dev.Backing.Parent) -and $PSCmdlet.ShouldProcess("VM [$($vmv.Name)]", "Convert $sizeGB GiB Thin Provision disk [$($dev.DeviceInfo.Label)] to [Thick Provision Eager Zeroed]"))
						{
							
							### Invoke 'Inflate virtual disk' task ###
							$ViDM = Get-View -Id 'VirtualDiskManager-virtualDiskManager' -Verbose:$false
							$taskMoRef = $ViDM.InflateVirtualDisk_Task($dev.Backing.FileName, $datacenter)
							$task = Get-View $taskMoRef -Verbose:$false
							
							### Show task progress ###
							For ($i = 1; $i -lt [int32]::MaxValue; $i++)
							{
								If ("running", "queued" -contains $task.Info.State)
								{
									$task.UpdateViewData("Info")
									If ($task.Info.Progress -ne $null)
									{
										Write-Progress -Activity "Inflate virtual disk task is in progress ..." -Status "VM [$($vmv.Name)]" `
													   -CurrentOperation "[$($dev.DeviceInfo.Label)] :: $($dev.Backing.FileName) [$sizeGB GiB]" `
													   -PercentComplete $task.Info.Progress -ErrorAction SilentlyContinue
										Start-Sleep -Seconds 3
									}
								}
								Else { Break }
							}
							
							### Get task completion results ###
							$tResult = $task.Info.State
							$tStart = $task.Info.StartTime
							$tEnd = $task.Info.CompleteTime
							$tCompleteTime = [Math]::Round((New-TimeSpan -Start $tStart -End $tEnd).TotalMinutes, 1)
							
							### Expand 'Datastore' and 'VMDK' from file path ###
							$null = $dev.Backing.FileName -match $regxVMDK
							
							$Properties = [ordered]@{
								VM = $vmv.Name
								VMHost = $esx.Name
								Datastore = $Matches.Datastore
								VMDK = $Matches.Filename
								HDLabel = $dev.DeviceInfo.Label
								HDSizeGB = $sizeGB
								Result = (Get-Culture).TextInfo.ToTitleCase($tResult)
								StartTime = $tStart
								CompleteTime = $tEnd
								TimeMin = $tCompleteTime
							}
							$Object = New-Object PSObject -Property $Properties
							$Object
						}
						Else { Write-Verbose "VM [$($vmv.Name)] :: [$($dev.DeviceInfo.Label)] :: $($dev.Backing.FileName) skipped" }
					}
				}
				$vmv.Reload()
			}
			Else { Write-Warning "VM [$($vmv.Name)] must be PoweredOff, but currently it is [$($vmv.Runtime.PowerState)]!" }
		}
	} #EndProcess
	
	End
	{
		Write-Progress -Activity "Completed" -Completed
		#Write-Progress -Completed $true -Status "Please wait"
	} #End
	
} #EndFunction Convert-VmdkThin2EZThick

Function Find-VcVm
{
	
<#
.SYNOPSIS
	Search VC's VM throw direct connection to group of ESXi Hosts.
.DESCRIPTION
	This script generates a list of ESXi Hosts with common suffix in a name,
	e.g. (esxprod1,esxprod2, ...) or (esxdev01,esxdev02, ...) etc. and
	searches VCenter's VM throw direct connection to this group of ESXi Hosts.
.PARAMETER VC
	VC's VM Name.
.PARAMETER HostSuffix
	ESXi Hosts' common suffix.
.PARAMETER PostfixStart
	ESXi Hosts' postfix number start.
.PARAMETER PostfixEnd
	ESXi Hosts' postfix number end.
.PARAMETER AddZero
	Add ESXi Hosts' postfix leading zero to one-digit postfix (from 01 to 09).
.EXAMPLE
	PS C:\> Find-VcVm vc1 esxprod 1 20 -AddZero
.EXAMPLE
	PS C:\> Find-VcVm -VC vc1 -HostSuffix esxdev -PostfixEnd 6
.EXAMPLE
	PS C:\> Find-VcVm vc1 esxprod |fl
.NOTES
	Author      :: Roman Gelman @rgelman75
	Limitation  :: [1] The function uses common credentials for all ESXi hosts.
	               [2] The hosts' Lockdown mode should be disabled.
	Version 1.0 :: 03-Sep-2015 :: [Release] :: Publicly available
	Version 1.1 :: 03-Aug-2016 :: [Improvement] :: Returned object properties changed
	Version 1.2 :: 14-Nov-2016 :: [Improvement] :: Disappear unnecessary error messages while disconnecting VC
.OUTPUTS
	[System.Management.Automation.PSCustomObject] PSObject collection.
.LINK
	https://ps1code.com
#>
	
	[Alias("Find-ViMVcVm")]
	Param (
		
		[Parameter(Mandatory = $true, Position = 1, HelpMessage = "vCenter's VM Name")]
		[Alias("vCenter", "VcVm")]
		[string]$VC
		 ,
		[Parameter(Mandatory = $true, Position = 2, HelpMessage = "ESXi Hosts' common suffix")]
		[Alias("VMHostSuffix", "ESXiSuffix")]
		[string]$HostSuffix
		 ,
		[Parameter(Mandatory = $false, Position = 3, HelpMessage = "ESXi Hosts' postfix number start")]
		[ValidateRange(1, 98)]
		[Alias("PostfixFirst", "Start")]
		[int]$PostfixStart = 1
		 ,
		[Parameter(Mandatory = $false, Position = 4, HelpMessage = "ESXi Hosts' postfix number end")]
		[ValidateRange(2, 99)]
		[Alias("PostfixLast", "End")]
		[int]$PostfixEnd = 9
		 ,
		[Parameter(Mandatory = $false, Position = 5, HelpMessage = "Add ESXi Hosts' postfix leading zero")]
		[switch]$AddZero = $false
	)
	
	Begin
	{
		
		Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Scope Session -Confirm:$false | Out-Null
		If ($PostfixEnd -le $PostfixStart) { Throw "PostfixEnd must be greater than PostfixStart" }
		Try { Disconnect-VIServer -Server $VC -Force -Confirm:$false -ErrorAction Stop }
		Catch { }
	}
	
	Process
	{
		
		$cred = Get-Credential -UserName root -Message "Common VMHost Credentials"
		If ($cred)
		{
			$hosts = @()
			
			For ($i = $PostfixStart; $i -le $PostfixEnd; $i++)
			{
				If ($AddZero -and $i -match '^\d{1}$')
				{
					$hosts += $HostSuffix + '0' + $i
				}
				Else
				{
					$hosts += $HostSuffix + $i
				}
			}
			
			Connect-VIServer $hosts -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -Credential $cred |
			select @{ N = 'VMHost'; E = { $_.Name } }, IsConnected | ft -AutoSize
			
			If ($global:DefaultVIServers.Length -ne 0)
			{
				$TargetVM = Get-VM -ErrorAction SilentlyContinue | ? { $_.Name -eq $VC }
				$VCHostname = $TargetVM.Guest.HostName
				$PowerState = $TargetVM.PowerState
				$VMHostHostname = $TargetVM.VMHost.Name
				Try { Disconnect-VIServer -Server "$HostSuffix*" -Force -Confirm:$false -ErrorAction Stop }
				Catch { }
			}
		}
	}
	
	End
	{
		
		If ($TargetVM)
		{
			$Properties = [ordered]@{
				VC = $VC
				Hostname = $VCHostname
				PowerState = $PowerState
				VMHost = $VMHostHostname
			}
			$Object = New-Object PSObject -Property $Properties
			$Object
		}
	}
	
} #EndFunction Find-VcVm

Function Set-PowerCLiTitle
{
	
<#
.SYNOPSIS
	Write connected VI servers info to the PowerCLi window title bar.
.DESCRIPTION
	This function writes connected VI servers info to the PowerCLi window/console title bar
	in the following format: [VIServerName :: ProductType (VCenter/VCSA/ESXi/SRM/VAMI)-ProductVersion].
.EXAMPLE
	PS C:\> Connect-VIServer VC1, VC2 -WarningAction SilentlyContinue
	PS C:\> Set-PowerCLiTitle
.EXAMPLE
	PS C:\> Connect-SrmServer $SRMServerName
	PS C:\> title
.EXAMPLE
	PS C:\> Connect-CisServer VCSA1, VCSA2 -WarningAction SilentlyContinue
	PS C:\> Set-PowerCLiTitle
.NOTES
	Author      :: Roman Gelman @rgelman75
	Version 1.0 :: 17-Nov-2015 :: [Release] :: Publicly available
	Version 1.1 :: 22-Aug-2016 :: [Improvement] :: Added support for SRM servers. Now the function differs berween VCSA and Windows VCenters. Minor visual changes
	Version 1.2 :: 11-Jan-2017 :: [Change] :: Now this is advanced function, minor code changes
	Version 1.3 :: 25-Oct-2017 :: [Improvement] :: Added support for VAMI servers, some code optimizations
.LINK
	https://ps1code.com/2015/11/17/set-powercli-title
#>
	
	[CmdletBinding()]
	[Alias("Set-ViMPowerCLiTitle", "title")]
	Param ()
	
	Begin
	{
		$VIS = $global:DefaultVIServers | ? { $_.IsConnected } | sort -Descending ProductLine, Name
		$SRM = $global:DefaultSrmServers | ? { $_.IsConnected } | sort -Descending ProductLine, Name
		$CIS = $global:DefaultCisServers | ? { $_.IsConnected } | sort Name
	}
	Process
	{
		### VI Servers ###
		foreach ($ConnectedVIS in $VIS)
		{
			$VIProduct = switch -exact ($ConnectedVIS.ProductLine)
			{
				'vpx' { if ($ConnectedVIS.ExtensionData.Content.About.OsType -match '^linux') { 'VCSA' } else { 'VCenter' }; Break }
				'embeddedEsx' { 'ESXi' }
				Default { $ConnectedVIS.ProductLine }
			}
			$Header += "[$($ConnectedVIS.Name) :: $VIProduct-$($ConnectedVIS.Version)] "
		}
		### SRM Servers ###
		foreach ($ConnectedSRM in $SRM)
		{
			$VIProduct = switch -exact ($ConnectedSRM.ProductLine)
			{
				'srm' { 'SRM' }
				Default { $ConnectedSRM.ProductLine }
			}
			$Header += "[$($ConnectedSRM.Name) :: $VIProduct-$($ConnectedSRM.Version)] "
		}
		
		### VAMI Servers ###
		$CIS | % { $Header += "[$($_.Name) :: VAMI] " }
	}
	End
	{
		if (!$VIS -and !$SRM -and !$CIS) { $Header = ':: Not connected to any VI Servers ::' }
		$Host.UI.RawUI.WindowTitle = $Header
	}
	
} #EndFunction Set-PowerCLiTitle

Filter Get-VMHostFirmwareVersion
{
	
<#
.SYNOPSIS
	Get ESXi host BIOS version.
.DESCRIPTION
	This filter returns ESXi host BIOS/UEFI Version and Release Date as a single string.
.EXAMPLE
	PS C:\> Get-VMHost 'esxprd1.*' |Get-VMHostFirmwareVersion
	Get single ESXi host's Firmware version.
.EXAMPLE
	PS C:\> Get-Cluster PROD |Get-VMHost |select Name,@{N='BIOS';E={$_ |Get-VMHostFirmwareVersion}}
	Get ESXi Name and Firmware version for single cluster.
.EXAMPLE
	PS C:\> Get-VMHost |sort Name |select Name,Version,Manufacturer,Model,@{N='BIOS';E={$_ |Get-VMHostFirmwareVersion}} |ft -au
	Add calculated property, that will contain Firmware version for all registered ESXi hosts.
.EXAMPLE
	PS C:\> Get-View -ViewType 'HostSystem' |select Name,@{N='BIOS';E={$_ |Get-VMHostFirmwareVersion}}
.EXAMPLE
	PS C:\> 'esxprd1.domain.com','esxdev2' |Get-VMHostFirmwareVersion
.INPUTS
	[VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost[]] Objects, returned by Get-VMHost cmdlet.
	[VMware.Vim.HostSystem[]] Objects, returned by Get-View cmdlet.
	[System.String[]] ESXi hostname or FQDN.
.OUTPUTS
	[System.String[]] BIOS/UEFI version and release date.
.NOTES
	Author: Roman Gelman @rgelman75
	Version 1.0 :: 09-Jan-2016 :: [Release] :: Publicly available
	Version 1.1 :: 03-Aug-2016 :: [Improvement] :: GetType() method replaced by -is to determine data type
.LINK
	https://ps1code.com/2016/01/09/esxi-bios-firmware-version-powercli
#>
	
	Try
	{
		If ($_ -is [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]) { $BiosInfo = ($_ | Get-View).Hardware.BiosInfo }
		ElseIf ($_ -is [VMware.Vim.HostSystem]) { $BiosInfo = $_.Hardware.BiosInfo }
		ElseIf ($_ -is [string]) { $BiosInfo = (Get-View -ViewType HostSystem -Filter @{ "Name" = $_ }).Hardware.BiosInfo }
		Else { Throw "Not supported data type as pipeline" }
		
		$fVersion = $BiosInfo.BiosVersion -replace ('^-\[|\]-$', $null)
		$fDate = [Regex]::Match($BiosInfo.ReleaseDate, '(\d{1,2}/){2}\d+').Value
		If ($fVersion) { return "$fVersion [$fDate]" }
		Else { return $null }
	}
	Catch
	{ }
} #EndFilter Get-VMHostFirmwareVersion
New-Alias -Name Get-ViMVMHostFirmwareVersion -Value Get-VMHostFirmwareVersion -Force:$true

Filter Get-VMHostBirthday
{
	
<#
.SYNOPSIS
	Get ESXi host installation date (Birthday).
.DESCRIPTION
	This filter returns ESXi host installation date.
.EXAMPLE
	PS C:\> Get-VMHost 'esxprd1.*' |Get-VMHostBirthday
	Get single ESXi host's Birthday.
.EXAMPLE
	PS C:\> Get-Cluster DEV |Get-VMHost |select Name,Version,@{N='Birthday';E={$_ |Get-VMHostBirthday}} |sort Name
	Get ESXi Name and Birthday for single cluster.
.EXAMPLE
	PS C:\> 'esxprd1.domain.com','esxprd2' |select @{N='ESXi';E={$_}},@{N='Birthday';E={$_ |Get-VMHostBirthday}}
	Pipe hostnames (strings) to the function.
.EXAMPLE
	PS C:\> Get-VMHost |select Name,@{N='Birthday';E={($_ |Get-VMHostBirthday).ToString('yyyy-MM-dd HH:mm:ss')}} |sort Name |ft -au
	Format output using ToString() method.
	http://blogs.technet.com/b/heyscriptingguy/archive/2015/01/22/formatting-date-strings-with-powershell.aspx
.INPUTS
	[VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost[]] Objects, returned by Get-VMHost cmdlet.
	[System.String[]] ESXi hostname or FQDN.
.OUTPUTS
	[System.DateTime[]] ESXi installation date/time.
.NOTES
	Original idea :: Magnus Andersson
	Author        :: Roman Gelman @rgelman75
	Requirement   :: vSphere 5.x or above
	Version 1.0   :: 05-Jan-2016 :: [Release] :: Publicly available
.LINK
	http://vcdx56.com/2016/01/05/find-esxi-installation-date/
#>
	
	Try
	{
		$EsxCli = Get-EsxCli -VMHost $_ -ErrorAction Stop
		$Uuid = $EsxCli.system.uuid.get()
		$bdHexa = [Regex]::Match($Uuid, '^(\w{8,})-').Groups[1].Value
		$bdDeci = [Convert]::ToInt64($bdHexa, 16)
		$bdDate = [TimeZone]::CurrentTimeZone.ToLocalTime(([DateTime]'1/1/1970').AddSeconds($bdDeci))
		If ($bdDate) { return $bdDate }
		Else { return $null }
	}
	Catch
	{ }
} #EndFilter Get-VMHostBirthday
New-Alias -Name Get-ViMVMHostBirthday -Value Get-VMHostBirthday -Force:$true

Function Enable-VMHostSSH
{
	
<#
.SYNOPSIS
	Enable SSH on all ESXi hosts in a cluster.
.DESCRIPTION
	This function enables SSH on all ESXi hosts in a cluster.
	It starts the TSM-SSH daemon and opens incoming TCP connections on port 22.
.PARAMETER Cluster
	Specifies Cluster object(s), returned by Get-Cluster cmdlet.
.EXAMPLE
	PS C:\> Get-Cluster PROD |Enable-VMHostSSH
.EXAMPLE
	PS C:\> Get-Cluster DEV,TEST |Enable-VMHostSSH |sort Cluster,VMHost |Format-Table -AutoSize
.EXAMPLE
	PS C:\> Get-Datacenter North |Get-Cluster |Enable-VMHostSSH -Confirm:$false
.NOTES
	Author      :: Roman Gelman @rgelman75
	Version 1.0 :: 07-Feb-2016 :: [Release] :: Publicly available
	Version 1.1 :: 02-Aug-2016 :: [Change]  :: -Cluster parameter data type changed to the portable type
	Version 1.2 :: 08-Jun-2017 :: [Improvement] :: -Confirm parameter supported
.LINK
	https://ps1code.com/2016/02/07/enable-disable-ssh-esxi-powercli
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	[Alias("Enable-ViMVMHostSSH", "essh")]
	[OutputType([PSCustomObject])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$WarningPreference = 'SilentlyContinue'
	}
	Process
	{
		foreach ($esx in (Get-VMHost -Location $Cluster))
		{
			if ('Connected', 'Maintenance' -contains $esx.ConnectionState -and $esx.PowerState -eq 'PoweredOn')
			{
				if ($PSCmdlet.ShouldProcess("VMHost [$($esx.Name)]", "Enable SSH"))
				{
					$sshSvc = Get-VMHostService -VMHost $esx | ? { $_.Key -eq 'TSM-SSH' } | Start-VMHostService -Confirm:$false
					$sshStatus = if ($sshSvc.Running) { 'Running' }
					else { 'NotRunning' }
					$fwRule = Get-VMHostFirewallException -VMHost $esx -Name 'SSH Server' | Set-VMHostFirewallException -Enabled $true
					
					[pscustomobject] @{
						Cluster = $Cluster.Name
						VMHost = $esx.Name
						State = $esx.ConnectionState
						PowerState = $esx.PowerState
						SSHDaemon = $sshStatus
						SSHEnabled = $fwRule.Enabled
					}
				}
			}
			else
			{
				[pscustomobject] @{
					Cluster = $Cluster.Name
					VMHost = $esx.Name
					State = $esx.ConnectionState
					PowerState = $esx.PowerState
					SSHDaemon = 'Unknown'
					SSHEnabled = 'Unknown'
				}
			}
		}
	}
	End
	{
		
	}
	
} #EndFunction Enable-VMHostSSH

Function Disable-VMHostSSH
{
	
<#
.SYNOPSIS
	Disable SSH on all ESXi hosts in a cluster.
.DESCRIPTION
	This function disables SSH on all ESXi hosts in a cluster.
	It stops the TSM-SSH daemon and optionally blocks incoming TCP connections on port 22.
.PARAMETER Cluster
	Specifies Cluster object(s), returned by Get-Cluster cmdlet.
.PARAMETER BlockFirewall
	If specified, try to disable "SSH Server" firewall exception rule.
	It might fail if this rule categorized as "Required Services" (VMware KB2037544).
.EXAMPLE
	PS C:\> Get-Cluster PROD |Disable-VMHostSSH -BlockFirewall
.EXAMPLE
	PS C:\> Get-Cluster DEV,TEST |Disable-VMHostSSH |sort Cluster,VMHost |Format-Table -AutoSize
.EXAMPLE
	PS C:\> Get-Cluster |Disable-VMHostSSH -Confirm:$false
.NOTES
	Author      :: Roman Gelman @rgelman75
	Version 1.0 :: 07-Feb-2016 :: [Release] :: Publicly available
	Version 1.1 :: 02-Aug-2016 :: [Change]  :: -Cluster parameter data type changed to the portable type
	Version 1.2 :: 08-Jun-2017 :: [Improvement] :: -Confirm parameter supported
.LINK
	https://ps1code.com/2016/02/07/enable-disable-ssh-esxi-powercli
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	[Alias("Disable-ViMVMHostSSH", "dssh")]
	[OutputType([PSCustomObject])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster
		 ,
		[Parameter(Mandatory = $false)]
		[switch]$BlockFirewall
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$WarningPreference = 'SilentlyContinue'
	}
	Process
	{
		foreach ($esx in (Get-VMHost -Location $Cluster))
		{
			if ('Connected', 'Maintenance' -contains $esx.ConnectionState -and $esx.PowerState -eq 'PoweredOn')
			{
				if ($PSCmdlet.ShouldProcess("VMHost [$($esx.Name)]", "Disable SSH"))
				{
					$sshSvc = Get-VMHostService -VMHost $esx | ? { $_.Key -eq 'TSM-SSH' } | Stop-VMHostService -Confirm:$false
					$sshStatus = if ($sshSvc.Running) { 'Running' }
					else { 'NotRunning' }
					$fwRule = Get-VMHostFirewallException -VMHost $esx -Name 'SSH Server'
					if ($BlockFirewall)
					{
						Try { $fwRule = Set-VMHostFirewallException -Exception $fwRule -Enabled:$false -Confirm:$false }
						Catch { }
					}
					
					[pscustomobject] @{
						Cluster = $Cluster.Name
						VMHost = $esx.Name
						State = $esx.ConnectionState
						PowerState = $esx.PowerState
						SSHDaemon = $sshStatus
						SSHEnabled = $fwRule.Enabled
					}
				}
			}
			else
			{
				[pscustomobject] @{
					Cluster = $Cluster.Name
					VMHost = $esx.Name
					State = $esx.ConnectionState
					PowerState = $esx.PowerState
					SSHDaemon = 'Unknown'
					SSHEnabled = 'Unknown'
				}
			}
		}
	}
	End
	{
		
	}
	
} #EndFunction Disable-VMHostSSH

Function Set-VMHostNtpServer
{
	
<#
.SYNOPSIS
	Set NTP servers setting on ESXi host(s).
.DESCRIPTION
	This function sets Time Configuration (NTP servers setting) on ESXi host(s)
	and restarts the NTP daemon to apply these settings.
.PARAMETER VMHost
	Specifies ESXi host object(s), returned by Get-VMHost cmdlet.
.PARAMETER NewNtp
	Specifies NTP servers (IP/Hostname/FQDN).
.EXAMPLE
	PS C:\> Get-VMHost |Set-VMHostNtpServer -NewNtp 'ntp1','ntp2' -Confirm:$false -Verbose
	Set two NTP servers to all ESXi hosts in inventory with no confirmation and verbose output.
.EXAMPLE
	PS C:\> Get-Cluster DEV, TEST |Get-VMHost |sort Parent, Name |Set-VMHostNtpServer -NewNtp 'ntp1.domain.com', '10.1.2.200' |ft -au
.EXAMPLE
	PS C:\> Get-VMHost -Location Datacenter1 |sort Name |Set-VMHostNtpServer 'ntp1.local.com', 'ntp2' -Verbose |epcsv -notype '.\Ntp_Report.csv'
	Export the results to the Excel.
.EXAMPLE
	PS C:\> Get-VMHost 'esx[1-9].*' |Set-VMHostNtpServer -NewNtp 'ntp1','ntp2'
.NOTES
	Author      :: Roman Gelman @rgelman75
	Version 1.0 :: 10-Mar-2016 :: [Release] :: Publicly available
	Version 1.1 :: 29-May-2017 :: [Change]  :: Supported -Confirm & -Verbose parameters. Progress bar added
.LINK
	https://ps1code.com/2016/03/10/set-esxi-ntp-powercli
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	[Alias("Set-ViMVMHostNtpServer", "setntp")]
	[OutputType([PSCustomObject])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost
		 ,
		[Parameter(Mandatory, Position = 1)]
		[string[]]$NewNtp
	)
	
	Begin
	{
		$WarningPreference = 'SilentlyContinue'
		$ErrorActionPreference = 'Stop'
		$FunctionName = '{0}' -f $MyInvocation.MyCommand
		Write-Verbose "$FunctionName started at [$(Get-Date)]"
	}
	Process
	{
		if ('Connected', 'Maintenance' -contains $VMHost.ConnectionState -and $VMHost.PowerState -eq 'PoweredOn')
		{
			if ($PSCmdlet.ShouldProcess("VMHost [$($VMHost.Name)]", "Set 'NTP servers' setting [$($NewNtp -join ', ')]"))
			{
				### Get current Ntp ###
				$Ntps = Get-VMHostNtpServer -vb:$false -VMHost $VMHost
				
				Write-Progress -Activity $FunctionName -Status "VMHost [$($VMHost.Name)]" -CurrentOperation "Remove NTP [$($Ntps -join ', ')] - Set NTP [$($NewNtp -join ', ')]"
				
				### Remove previously configured Ntp ###
				$removed = $false
				Try
				{
					Remove-VMHostNtpServer -vb:$false -NtpServer $Ntps -VMHost $VMHost -Confirm:$false
					$removed = $true
				}
				Catch { }
				
				### Add new Ntp ###
				$added = $null
				Try
				{
					$added = Add-VMHostNtpServer -vb:$false -NtpServer $NewNtp -VMHost $VMHost -Confirm:$false
				}
				Catch { }
				
				### Restart NTP Daemon ###
				$restarted = $false
				Try
				{
					if ($added) { Get-VMHostService -vb:$false -VMHost $VMHost | ? { $_.Key -eq 'ntpd' } | Restart-VMHostService -vb:$false -Confirm:$false | Out-Null }
					$restarted = $true
				}
				Catch { }
				
				### Return results ###
				[pscustomobject] @{
					VMHost = $VMHost
					OldNtp = $Ntps
					IsOldRemoved = $removed
					NewNtp = $added
					IsDaemonRestarted = $restarted
				}
			}
		}
		else
		{
			Write-Verbose "The VMHost [$($VMHost.Name)] is in unsupported state"
		}
	}
	End
	{
		Write-Verbose "$FunctionName finished at [$(Get-Date)]"
	}
} #EndFunction Set-VMHostNtpServer

Function Get-Version
{
	
<#
.SYNOPSIS
	Get VMware Virtual Infrastructure objects' version info.
.DESCRIPTION
	This cmdlet gets VMware Virtual Infrastructure objects' version info.
.PARAMETER VIObject
	Vitual Infrastructure objects (VM, VMHosts, DVSwitches, Datastores).
.PARAMETER VCenter
	Get versions for all connected VCenter servers/ESXi hosts and PowerCLi version on the localhost.
.PARAMETER LicenseKey
	Get versions of license keys.
.EXAMPLE
	PS C:\> Get-VMHost |Get-Version |? {$_.Version -ge 5.5 -and $_.Version.Revision -lt 2456374}
	Get all ESXi v5.5 hosts that have Revision less than 2456374.
.EXAMPLE
	PS C:\> Get-View -ViewType HostSystem |Get-Version |select ProductName,Version |sort Version |group Version |sort Count |select Count,@{N='Version';E={$_.Name}},@{N='VMHost';E={($_.Group |select -expand ProductName) -join ','}} |epcsv -notype 'C:\reports\ESXi_Version.csv'
	Group all ESXi hosts by Version and export the list to CSV.
.EXAMPLE
	PS C:\> Get-VM |Get-Version |? {$_.FullVersion -match 'v10' -and $_.Version -gt 9.1}
	Get all VM with Virtual Hardware v10 and VMTools version above v9.1.0.
.EXAMPLE
	PS C:\> Get-Version -VCenter |Format-Table -AutoSize
	Get all connected VCenter servers/ESXi hosts versions and PowerCLi version.
.EXAMPLE
	PS C:\> Get-VDSwitch |Get-Version |sort Version |? {$_.Version -lt 5.5}
	Get all DVSwitches that have version below 5.5.
.EXAMPLE
	PS C:\> Get-Datastore |Get-Version |? {$_.Version.Major -eq 3}
	Get all VMFS3 datastores.
.EXAMPLE
	PS C:\> Get-Version -LicenseKey
	Get license keys version info.
.INPUTS
	Output objects from the following cmdlets:
	Get-VMHost, Get-VM, Get-DistributedSwitch, Get-Datastore and Get-View -ViewType HostSystem.
.OUTPUTS
	[System.Management.Automation.PSCustomObject] PSObject collection.
.NOTES
	Author      :: Roman Gelman @rgelman75
	Version 1.0 :: 23-May-2016 :: Release :: Publicly available
	Version 1.1 :: 03-Aug-2016 :: Bugfix :: VDSwitch data type changed. Function Get-VersionVDSwitch edited
.LINK
	https://ps1code.com/2016/05/25/get-version-powercli
#>
	
	[CmdletBinding(DefaultParameterSetName = 'VIO')]
	[Alias("Get-ViMVersion")]
	Param (
		
		[Parameter(Mandatory, Position = 1, ValueFromPipeline = $true, ParameterSetName = 'VIO')]
		$VIObject
		 ,
		[Parameter(Mandatory, Position = 1, ParameterSetName = 'VC')]
		[switch]$VCenter
		 ,
		[Parameter(Mandatory, Position = 1, ParameterSetName = 'LIC')]
		[switch]$LicenseKey
	)
	
	Begin
	{
		
		$ErrorActionPreference = 'SilentlyContinue'
		
		Function Get-VersionVMHostImpl
		{
			Param ([Parameter(Mandatory, Position = 1)]
				$InputObject)
			$ErrorActionPreference = 'Stop'
			Try
			{
				If ('Connected', 'Maintenance' -contains $InputObject.ConnectionState -and $InputObject.PowerState -eq 'PoweredOn')
				{
					$ProductInfo = $InputObject.ExtensionData.Config.Product
					$ProductVersion = [version]($ProductInfo.Version + '.' + $ProductInfo.Build)
					
					$Properties = [ordered]@{
						ProductName = $InputObject.Name
						ProductType = $ProductInfo.Name
						FullVersion = $ProductInfo.FullName
						Version = $ProductVersion
					}
				}
				Else
				{
					$Properties = [ordered]@{
						ProductName = $InputObject.Name
						ProductType = 'VMware ESXi'
						FullVersion = 'Unknown'
						Version = [version]'0.0.0.0'
					}
				}
			}
			Catch
			{
				$Properties = [ordered]@{
					ProductName = $InputObject.Name
					ProductType = 'VMware ESXi'
					FullVersion = 'Unknown'
					Version = [version]'0.0.0.0'
				}
			}
			Finally
			{
				$Object = New-Object PSObject -Property $Properties
				$Object
			}
			
		} #EndFunction Get-VersionVMHostImpl
		
		Function Get-VersionVMHostView
		{
			Param ([Parameter(Mandatory, Position = 1)]
				$InputObject)
			$ErrorActionPreference = 'Stop'
			Try
			{
				$ProductRuntime = $InputObject.Runtime
				If ('connected', 'maintenance' -contains $ProductRuntime.ConnectionState -and $ProductRuntime.PowerState -eq 'poweredOn')
				{
					$ProductInfo = $InputObject.Config.Product
					$ProductVersion = [version]($ProductInfo.Version + '.' + $ProductInfo.Build)
					
					$Properties = [ordered]@{
						ProductName = $InputObject.Name
						ProductType = $ProductInfo.Name
						FullVersion = $ProductInfo.FullName
						Version = $ProductVersion
					}
				}
				Else
				{
					$Properties = [ordered]@{
						ProductName = $InputObject.Name
						ProductType = 'VMware ESXi'
						FullVersion = 'Unknown'
						Version = [version]'0.0.0.0'
					}
				}
			}
			Catch
			{
				$Properties = [ordered]@{
					ProductName = $InputObject.Name
					ProductType = 'VMware ESXi'
					FullVersion = 'Unknown'
					Version = [version]'0.0.0.0'
				}
			}
			Finally
			{
				$Object = New-Object PSObject -Property $Properties
				$Object
			}
			
		} #EndFunction Get-VersionVMHostView
		
		Function Get-VersionVM
		{
			Param ([Parameter(Mandatory, Position = 1)]
				$InputObject)
			$ErrorActionPreference = 'Stop'
			Try
			{
				$ProductInfo = $InputObject.Guest
				
				If ($InputObject.ExtensionData.Guest.ToolsStatus -ne 'toolsNotInstalled' -and $ProductInfo)
				{
					$ProductVersion = [version]$ProductInfo.ToolsVersion
					
					$Properties = [ordered]@{
						ProductName = $InputObject.Name
						ProductType = $InputObject.ExtensionData.Config.GuestFullName #$ProductInfo.OSFullName
						FullVersion = "VMware VM " + $InputObject.Version
						Version = $ProductVersion
					}
				}
				Else
				{
					
					$Properties = [ordered]@{
						ProductName = $InputObject.Name
						ProductType = $InputObject.ExtensionData.Config.GuestFullName
						FullVersion = "VMware VM " + $InputObject.Version
						Version = [version]'0.0.0'
					}
				}
			}
			Catch
			{
				$Properties = [ordered]@{
					ProductName = $InputObject.Name
					ProductType = 'Unknown'
					FullVersion = 'VMware VM'
					Version = [version]'0.0.0'
				}
			}
			Finally
			{
				$Object = New-Object PSObject -Property $Properties
				$Object
			}
			
		} #EndFunction Get-VersionVM
		
		Function Get-VersionPowerCLi
		{
			$ErrorActionPreference = 'Stop'
			Try
			{
				$PCLi = Get-PowerCLIVersion
				$PCLiVer = [string]$PCLi.Major + '.' + [string]$PCLi.Minor + '.' + [string]$PCLi.Revision + '.' + [string]$PCLi.Build
				
				$Properties = [ordered]@{
					ProductName = $env:COMPUTERNAME
					ProductType = 'VMware vSphere PowerCLi'
					FullVersion = $PCLi.UserFriendlyVersion
					Version = [version]$PCLiVer
				}
				$Object = New-Object PSObject -Property $Properties
				$Object
			}
			Catch { }
		} #EndFunction Get-VersionPowerCLi
		
		Function Get-VersionVCenter
		{
			Param ([Parameter(Mandatory, Position = 1)]
				$InputObject)
			$ErrorActionPreference = 'Stop'
			Try
			{
				If ($obj.IsConnected)
				{
					$ProductInfo = $InputObject.ExtensionData.Content.About
					$ProductVersion = [version]($ProductInfo.Version + '.' + $ProductInfo.Build)
					Switch -regex ($ProductInfo.OsType)
					{
						'^win'   { $ProductFullName = $ProductInfo.Name + ' Windows'; Break }
						'^linux' { $ProductFullName = $ProductInfo.Name + ' Appliance'; Break }
						Default { $ProductFullName = $ProductInfo.Name; Break }
					}
					
					$Properties = [ordered]@{
						ProductName = $InputObject.Name
						ProductType = $ProductFullName
						FullVersion = $ProductInfo.FullName
						Version = $ProductVersion
					}
				}
				Else
				{
					$Properties = [ordered]@{
						ProductName = $InputObject.Name
						ProductType = 'VMware vCenter Server'
						FullVersion = 'Unknown'
						Version = [version]'0.0.0.0'
					}
				}
			}
			Catch
			{
				$Properties = [ordered]@{
					ProductName = $InputObject.Name
					ProductType = 'VMware vCenter Server'
					FullVersion = 'Unknown'
					Version = [version]'0.0.0.0'
				}
			}
			Finally
			{
				$Object = New-Object PSObject -Property $Properties
				$Object
			}
			
		} #EndFunction Get-VersionVCenter
		
		Function Get-VersionVDSwitch
		{
			Param ([Parameter(Mandatory, Position = 1)]
				$InputObject)
			$ErrorActionPreference = 'Stop'
			$ProductTypeName = 'VMware DVSwitch'
			Try
			{
				$ProductInfo = $InputObject.ExtensionData.Summary.ProductInfo
				$ProductFullVersion = 'VMware Distributed Virtual Switch ' + $ProductInfo.Version + ' build-' + $ProductInfo.Build
				$ProductVersion = [version]($ProductInfo.Version + '.' + $ProductInfo.Build)
				
				$Properties = [ordered]@{
					ProductName = $InputObject.Name
					ProductType = $ProductTypeName
					FullVersion = $ProductFullVersion
					Version = $ProductVersion
				}
			}
			Catch
			{
				$Properties = [ordered]@{
					ProductName = $InputObject.Name
					ProductType = $ProductTypeName
					FullVersion = 'Unknown'
					Version = [version]'0.0.0.0'
				}
			}
			Finally
			{
				$Object = New-Object PSObject -Property $Properties
				$Object
			}
			
		} #EndFunction Get-VersionVDSwitch
		
		Function Get-VersionDatastore
		{
			Param ([Parameter(Mandatory, Position = 1)]
				$InputObject)
			$ErrorActionPreference = 'Stop'
			$ProductTypeName = 'VMware VMFS Datastore'
			Try
			{
				$ProductVersionNumber = $InputObject.FileSystemVersion
				$ProductFullVersion = 'VMware Datastore VMFS v' + $ProductVersionNumber
				$ProductVersion = [version]$ProductVersionNumber
				
				$Properties = [ordered]@{
					ProductName = $InputObject.Name
					ProductType = $ProductTypeName
					FullVersion = $ProductFullVersion
					Version = $ProductVersion
				}
			}
			Catch
			{
				$Properties = [ordered]@{
					ProductName = $InputObject.Name
					ProductType = $ProductTypeName
					FullVersion = 'Unknown'
					Version = [version]'0.0'
				}
			}
			Finally
			{
				$Object = New-Object PSObject -Property $Properties
				$Object
			}
			
		} #EndFunction Get-VersionDatastore
		
		Function Get-VersionLicenseKey
		{
			Param ([Parameter(Mandatory, Position = 1)]
				$InputObject)
			$ErrorActionPreference = 'Stop'
			$ProductTypeName = 'License Key'
			Try
			{
				$InputObjectProp = $InputObject | select -ExpandProperty Properties
				Foreach ($prop in $InputObjectProp)
				{
					If ($prop.Key -eq 'ProductName') { $ProductType = $prop.Value + ' ' + $ProductTypeName }
					ElseIf ($prop.Key -eq 'ProductVersion') { $ProductVersion = [version]$prop.Value }
				}
				
				Switch -regex ($InputObject.CostUnit)
				{
					'^cpu'     { $LicCostUnit = 'CPU'; Break }
					'^vm'      { $LicCostUnit = 'VM'; Break }
					'server'   { $LicCostUnit = 'SRV'; Break }
					Default { $LicCostUnit = $InputObject.CostUnit }
					
				}
				
				$ProductFullVersion = $InputObject.Name + ' [' + $InputObject.Used + '/' + $InputObject.Total + $LicCostUnit + ']'
				
				$Properties = [ordered]@{
					ProductName = $InputObject.LicenseKey
					ProductType = $ProductType
					FullVersion = $ProductFullVersion
					Version = $ProductVersion
				}
			}
			Catch
			{
				$Properties = [ordered]@{
					ProductName = $InputObject.LicenseKey
					ProductType = $ProductTypeName
					FullVersion = 'Unknown'
					Version = [version]'0.0'
				}
			}
			Finally
			{
				$Object = New-Object PSObject -Property $Properties
				If ($InputObject.EditionKey -ne 'eval') { $Object }
			}
			
		} #EndFunction Get-VersionLicenseKey
		
	}
	
	Process
	{
		
		If ($PSCmdlet.ParameterSetName -eq 'VIO')
		{
			Foreach ($obj in $VIObject)
			{
				If ($obj -is [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]) { Get-VersionVMHostImpl -InputObject $obj }
				ElseIf ($obj -is [VMware.Vim.HostSystem]) { Get-VersionVMHostView -InputObject $obj }
				ElseIf ($obj -is [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]) { Get-VersionVM -InputObject $obj }
				ElseIf ($obj -is [VMware.VimAutomation.Vds.Types.V1.VmwareVDSwitch]) { Get-VersionVDSwitch -InputObject $obj }
				ElseIf ($obj -is [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.VmfsDatastore]) { Get-VersionDatastore -InputObject $obj }
				Else { Write-Warning "Not supported object type" }
			}
		}
		ElseIf ($PSCmdlet.ParameterSetName -eq 'VC')
		{
			If ($global:DefaultVIServers.Length) { Foreach ($obj in $global:DefaultVIServers) { Get-VersionVCenter -InputObject $obj } }
			Else { Write-Warning "Please use 'Connect-VIServer' cmdlet to connect to VCenter servers or ESXi hosts." }
			Get-VersionPowerCLi
		}
		ElseIf ($PSCmdlet.ParameterSetName -eq 'LIC')
		{
			If ($global:DefaultVIServers.Length) { Foreach ($obj in ((Get-View (Get-View ServiceInstance).Content.LicenseManager).Licenses)) { Get-VersionLicenseKey -InputObject $obj } }
			Else { Write-Warning "Please use 'Connect-VIServer' cmdlet to connect to VCenter servers or ESXi hosts." }
		}
	}
	
	End { }
	
} #EndFunction Get-Version

Function Search-Datastore
{
	
<#
.SYNOPSIS
	Search files on VMware Datastores.
.DESCRIPTION
	This function searches files on VMware Datastore(s).
.PARAMETER Datastore
	Specifies Datastore object(s), returtned by Get-Datastore cmdlet or Datastore name.
.PARAMETER FileName
	Specifies file name pattern, the default is to search all files (*).
.PARAMETER FileType
	Specifies file type(s) to search, the default is to search all existing files.
.EXAMPLE
	PS C:\> Get-Datastore | Search-Datastore
	Search all files on all Datastores.
.EXAMPLE
	PS C:\> Get-Datastore datastore* | Search-Datastore -FileType Vmdk,Iso
	Search all [*.vmdk] & [*.iso] files on several Datastores.
.EXAMPLE
	PS C:\> Get-DatastoreCluster backup | Get-Datastore | Search-Datastore Iso win -Verbose | ogv
	Search [*win*.iso] files on all SDRS cluster members. Output Datastore names to the console.
.EXAMPLE
	PS C:\> Search-Datastore -Datastore localssd -FileName vm1* | Format-Table -AutoSize
	Search the specific VM related files [vm1*.*] on the Datastore named [localssd].
.EXAMPLE
	PS C:\> Get-Datastore | Search-Datastore -FileType Vmdk -Orphaned | ? { $_.DaysInactive -gt 365 } | sort DaysInactive -desc | epcsv .\Orphaned.csv' -notype
	Export to the Excel orphaned [*.vmdk] files that were inactive more than one year.
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5.2
	Platform    :: Tested on vSphere 5.5/6.5 | VCenter 5.5U2/VCSA 6.5U1 | NetApp/Isilon/VMAX NFS & VMFS datastores
	Version 1.0 :: 09-Aug-2016 :: [Release] :: Publicly available
	Version 1.1 :: 19-Sep-2016 :: [Bugfix] :: Some SAN as NetApp return *-flat.vmdk files in the search. Such files were recognized as orphaned. [Changed Block Tracking Disk] file type was renamed to [CBT Disk]
	Version 1.2 :: 17-Dec-2017 :: [Change] :: The -VerboseDatastoreName parameter deprecated and replaced by the common -Verbose. Minor code and examples changes
	Version 1.3 :: 18-Dec-2017 :: [Feature] :: VSAN Datastore support
	Version 1.4 :: 10-Feb-2018 :: [Change] :: Added descriptions for several new file types. Code optimizations
	Version 1.5 :: 15-Feb-2018 :: [Change] :: Available values for the -FileType parameter have changed
	Version 1.6 :: 18-Feb-2018 :: [Feature] :: New -Orphaned parameter added. Parameters aliases removed
	Version 2.0 :: 22-Feb-2018 :: [Feature] :: Multiple file types supoprted by -FileType parameter
.LINK
	https://ps1code.com/2016/08/21/search-datastores-powercli
#>
	
	[CmdletBinding()]
	[Alias("Search-ViMDatastore", "dsbrowse")]
	[OutputType([pscustomobject])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		$Datastore
		 ,
		[Parameter(Mandatory = $false, Position = 1)]
		[string]$FileName = "*"
		 ,
		[Parameter(Mandatory = $false, Position = 0)]
		[ValidateSet("Vmdk", "Iso", "Template", "Bundle", "Vmx")]
		[string[]]$FileType
		 ,
		[Parameter(Mandatory = $false)]
		[switch]$Orphaned
	)
	
	Begin
	{
		$i = 0
		$Now = [datetime]::Now
		$rgxFileExt = '^(?<FileName>.+)\.(?<Ext>.+)$'
		
		Write-Progress -Activity "Generating Used Disks list" -Status "In progress ..."
		$UsedDisks = Get-View -Verbose:$false -ViewType VirtualMachine | % { $_.Layout } | % { $_.Disk } | % { $_.DiskFile }
		Write-Progress -Activity "Completed" -Completed
		
		$FileTypes = @{
			'dumpfile' = 'ESXi Coredump';
			'iso' = 'CD/DVD Image';
			'vmdk' = 'Virtual Disk';
			'vmtx' = 'Template';
			'vmx' = 'VM Config';
			'lck' = 'Config Lock';
			'vmx~' = 'Config Backup';
			'vmxf' = 'Supplemental Config';
			'vmsd' = 'Snapshot Metadata';
			'vmsn' = 'Snapshot Memory';
			'vmss' = 'Suspended State';
			'vmem' = 'Paging';
			'vswp' = 'Swap'
			'nvram' = 'BIOS State';
			'log' = 'VM Log';
			'vib' = 'Patch/Bundle';
			'zip' = 'Patch/Archive';
			'flp' = 'Floppy Image';
			'hlog' = 'SvMotion Tracker';
			'' = 'Unknown'
		}
		
		if ($FileName -notmatch '\*') { $FileName = "*$FileName*" }
		
		$FilePattern = @()
		$FilePattern += if ($PSBoundParameters.ContainsKey('FileType'))
		{
			switch ($FileType)
			{
				{ $_ -contains 'Vmdk' } { @(($FileName + '.vmdk')) }
				{ $_ -contains 'Iso' } { @(($FileName + '.iso')) }
				{ $_ -contains 'Template' } { @(($FileName + '.vmtx')) }
				{ $_ -contains 'Bundle' } { @(($FileName + '.vib'), ($FileName + '.zip')) }
				{ $_ -contains 'Vmx' } { @(($FileName + '.vmx')) }
			}
		}
		else
		{
			@(($FileName + '.*'))
		}
	}
	Process
	{
		$DsView = switch ($Datastore)
		{
			{
				$_ -is [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.VmfsDatastore] -or `
				$_ -is [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.NasDatastore] -or `
				$_ -is [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]
			}
			{ Get-View -Verbose:$false -VIObject $Datastore }
			
			{ $_ -is [string] }
			{ Get-View -Verbose:$false -ViewType Datastore | ? { $_.Name -eq $Datastore } }
			
			Default { Throw "Not supported object type" }
		}
		
		if ($DsView)
		{
			$i += 1
			
			$DsCapacityGB = $DsView.Summary.Capacity/1GB
			
			Write-Progress -Activity "Datastore Browser is working now ..." `
						   -Status ("Searching for files on Datastore [$($DsView.Name)]") `
						   -CurrentOperation ("Search criteria [" + ($FilePattern -join (', ')) + "]")
			
			$fileQueryFlags = New-Object VMware.Vim.FileQueryFlags
			$fileQueryFlags.FileSize = $true
			$fileQueryFlags.FileType = $true
			$fileQueryFlags.Modification = $true
			
			$searchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
			$searchSpec.Details = $fileQueryFlags
			$searchSpec.MatchPattern = $FilePattern
			$searchSpec.SortFoldersFirst = $true
			
			$DsBrowser = Get-View $DsView.Browser -Verbose:$false
			$rootPath = "[$($DsView.Name)]"
			$searchResult = $DsBrowser.SearchDatastoreSubFolders($rootPath, $searchSpec)
			
			foreach ($folder in $searchResult)
			{
				foreach ($fileResult in $folder.File)
				{
					if ($fileResult.Path)
					{
						if ($fileResult.FileSize/1GB -lt 1) { $Round = 3 }
						else { $Round = 0 }
						$SizeGiB = [Math]::Round($fileResult.FileSize/1GB, $Round)
						
						$File = [regex]::Match($fileResult.Path, $rgxFileExt)
						$FileBody = $File.Groups['FileName'].Value
						$ShortExt = $File.Groups['Ext'].Value
						
						$LongExt = if ($FileTypes.ContainsKey($ShortExt)) { $FileTypes.$ShortExt }
						else { '.' + $ShortExt.ToUpper() }
						
						if ($ShortExt -eq 'vmdk')
						{
							if ($FileBody -match '-ctk$') { $LongExt = 'CBT Disk' }
							else
							{
								if ($FileBody -match '-(\d{6}|delta)$') { $LongExt = 'Snapshot Disk' }
								if ($UsedDisks -notcontains ($folder.FolderPath + $fileResult.Path) -and $FileBody -notmatch '-flat$') { $LongExt = 'Orphaned ' + $LongExt }
							}
						}
						
						$ViFile = [pscustomobject]@{
							Datastore = $DsView.Name
							Folder = [regex]::Match($folder.FolderPath, '\]\s(?<Folder>.+)/').Groups[1].Value
							File = $fileResult.Path
							FileType = $LongExt
							SizeGB = $SizeGiB
							SizeBar = New-PercentageBar -Value $SizeGiB -MaxValue $DsCapacityGB
							Modified = ([datetime]$fileResult.Modification).ToString('dd-MMM-yyyy HH:mm')
							DaysInactive = (New-TimeSpan -Start ($fileResult.Modification) -End $Now).Days
						}
						if ($Orphaned) { if ($ViFile.FileType -match '^Orphaned') { $ViFile } }
						else { $ViFile }
					}
				}
			}
			Write-Verbose "Datastore N$([char][byte]186)$i [$($DsView.Name)] search is finished"
		}
	}
	End { Write-Progress -Activity "Completed" -Completed }
	
} #EndFunction Search-Datastore

Function Compare-VMHost
{
	
<#
.SYNOPSIS
	Compare two or more ESXi hosts on different criteria.
.DESCRIPTION
	This function compares two or more ESXi hosts on different criteria.
.PARAMETER ReferenceVMHost
	Specifies reference ESXi host object, returned by Get-VMHost cmdlet.
.PARAMETER DifferenceVMHost
	Specifies difference ESXi host object(s), returned by Get-VMHost cmdlet.
.PARAMETER Compare
	Specifies what to compare.
.PARAMETER Truncate
	If specified, try to truncate ESXi hostname.
.PARAMETER HideReference
	If specified, filter out reference host related objects from the output.
.EXAMPLE
	PS C:\> Get-VMHost 'esx2[78].*' |Compare-VMHost -ReferenceVMHost (Get-VMHost 'esx21.*') -Compare SharedDatastore
	Compare shared datastores of two ESXi hosts (esx27, esx28) with the reference ESXi host (esx21).
.EXAMPLE
	PS C:\> Get-VMHost 'esx2.*' |Compare-VMHost (Get-VMHost 'esx1.*') VIB -Truncate -HideReference
	Compare VIBs between two ESXi hosts, truncate hostnames and return difference hosts only.
.EXAMPLE
	PS C:\> Get-Cluster DEV |Get-VMHost 'esx2.*' |Compare-VMHost -ref (Get-VMHost 'esx1.*') -Compare LUN -Verbose |epcsv -notype .\LUNID.csv
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0|PowerCLi 6.5.1
	Platform    :: Tested on vSphere 5.5/6.5|VCenter 5.5U2/VCSA 6.5
	Requirement :: VIB compare (-Compare VIB) supported on ESXi/VC 5.0 and later
	Version 1.0 :: 26-Sep-2016 :: [Release]
	Version 1.1 :: 29-May-2017 :: [Change] Added NTP & VIB compare, -HideReference parameter and Progress bar
.LINK
	https://ps1code.com/2016/09/26/compare-esxi-powercli
#>
	
	[CmdletBinding()]
	[Alias("Compare-ViMVMHost", "diffesx")]
	[OutputType([PSCustomObject])]
	Param (
		[Parameter(Mandatory, Position = 1)]
		[Alias("ref")]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$ReferenceVMHost
		 ,
		[Parameter(Mandatory, ValueFromPipeline)]
		[Alias("diff")]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$DifferenceVMHost
		 ,
		[Parameter(Mandatory = $false, Position = 2)]
		[ValidateSet("NAA", "LUN", "Datastore", "SharedDatastore", "Portgroup", "NTP", "VIB")]
		[string]$Compare = 'SharedDatastore'
		 ,
		[Parameter(Mandatory = $false)]
		[Alias("TruncateVMHostName")]
		[switch]$Truncate
		 ,
		[Parameter(Mandatory = $false)]
		[switch]$HideReference
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$WarningPreference = 'SilentlyContinue'
		$FunctionName = '{0}' -f $MyInvocation.MyCommand
		Write-Verbose "$FunctionName started at [$(Get-Date)]"
		
		if ('Connected', 'Maintenance' -contains $ReferenceVMHost.ConnectionState -and $ReferenceVMHost.PowerState -eq 'PoweredOn')
		{
			Try
			{
				$RefHost = Switch -exact ($Compare)
				{
					'LUN'
					{
						(Get-ScsiLun -vb:$false -VmHost $ReferenceVMHost -LunType 'disk' | select @{ N = 'LUN'; E = { ([regex]::Match($_.RuntimeName, ':L(\d+)$').Groups[1].Value) -as [int] } } | sort LUN).LUN
						Break
					}
					'NAA'
					{
						(Get-ScsiLun -vb:$false -VmHost $ReferenceVMHost -LunType 'disk' | select CanonicalName | sort CanonicalName).CanonicalName
						Break
					}
					'Datastore'
					{
						($ReferenceVMHost | Get-Datastore -vb:$false | select Name | sort Name).Name
						Break
					}
					'SharedDatastore'
					{
						($ReferenceVMHost | Get-Datastore -vb:$false | ? { $_.ExtensionData.Summary.MultipleHostAccess } | select Name | sort Name).Name
						Break
					}
					'Portgroup'
					{
						(($ReferenceVMHost).NetworkInfo.ExtensionData.Portgroup).Spec.Name + ($ReferenceVMHost | Get-VDSwitch -vb:$false | Get-VDPortgroup -vb:$false | ? { !$_.IsUplink } | select Name | sort Name).Name
						Break
					}
					'NTP'
					{
						($ReferenceVMHost | Get-VMHostNtpServer -vb:$false) -join ', '
						Break
					}
					'VIB'
					{
						((Get-EsxCli -vb:$false -V2 -VMHost $ReferenceVMHost).software.vib.list.Invoke()).ID
					}
				}
			}
			Catch
			{
				"{0}" -f $Error.Exception.Message
			}
		}
		else
		{
			Write-Verbose "The reference host [$($ReferenceVMHost.Name)] currently is in [$($ReferenceVMHost.ConnectionState)::$($ReferenceVMHost.PowerState)] state. The compare was canceled"
		}
	}
	Process
	{
		if ('Connected', 'Maintenance' -contains $DifferenceVMHost.ConnectionState -and $DifferenceVMHost.PowerState -eq 'PoweredOn')
		{
			Write-Progress -Activity $FunctionName -Status "Comparing [$Compare] with Reference VMHost [$($ReferenceVMHost.Name)]" -CurrentOperation "Current VMHost [$($DifferenceVMHost.Name)]"
			
			Try
			{
				$DifHost = Switch -exact ($Compare)
				{
					
					'LUN'
					{
						(Get-ScsiLun -vb:$false -VmHost $DifferenceVMHost -LunType 'disk' | select @{ N = 'LUN'; E = { ([regex]::Match($_.RuntimeName, ':L(\d+)$').Groups[1].Value) -as [int] } } | sort LUN).LUN
						Break
					}
					'NAA'
					{
						(Get-ScsiLun -vb:$false -VmHost $DifferenceVMHost -LunType 'disk' | select CanonicalName | sort CanonicalName).CanonicalName
						Break
					}
					'Datastore'
					{
						($DifferenceVMHost | Get-Datastore -vb:$false | select Name | sort Name).Name
						Break
					}
					'SharedDatastore'
					{
						($DifferenceVMHost | Get-Datastore -vb:$false | ? { $_.ExtensionData.Summary.MultipleHostAccess } | select Name | sort Name).Name
						Break
					}
					'Portgroup'
					{
						(($DifferenceVMHost).NetworkInfo.ExtensionData.Portgroup).Spec.Name + ($DifferenceVMHost | Get-VDSwitch -vb:$false | Get-VDPortgroup -vb:$false | ? { !$_.IsUplink } | select Name | sort Name).Name
						Break
					}
					'NTP'
					{
						($DifferenceVMHost | Get-VMHostNtpServer -vb:$false) -join ', '
						Break
					}
					'VIB'
					{
						((Get-EsxCli -vb:$false -V2 -VMHost $DifferenceVMHost).software.vib.list.Invoke()).ID
					}
				}
				
				$diffObj = Compare-Object -ReferenceObject $RefHost -DifferenceObject $DifHost -IncludeEqual:$false -CaseSensitive
				
				foreach ($diff in $diffObj)
				{
					if ($diff.SideIndicator -eq '=>')
					{
						$diffOwner = $DifferenceVMHost.Name
						$Reference = $false
						$Difference = ''
					}
					else
					{
						$diffOwner = $ReferenceVMHost.Name
						$Reference = $true
						$Difference = $DifferenceVMHost.Name
					}
					
					if ($Truncate)
					{
						$diffOwner = [regex]::Match($diffOwner, '^(.+?)(\.|$)').Groups[1].Value
						$Difference = [regex]::Match($Difference, '^(.+?)(\.|$)').Groups[1].Value
					}
					
					$res = [pscustomobject] @{
						$Compare = $diff.InputObject
						VMHost = $diffOwner
						Reference = $Reference
						Difference = $Difference
					}
					
					if ($HideReference) { if (!$res.Reference) { $res } }
					else { $res }
				}
			}
			Catch
			{
				"{0}" -f $Error.Exception.Message
			}
		}
		else
		{
			Write-Verbose "The difference host [$($DifferenceVMHost.Name)] currently is in [$($DifferenceVMHost.ConnectionState)::$($DifferenceVMHost.PowerState)] state. The host was skipped"
		}
	}
	End
	{
		Write-Verbose "$FunctionName finished at [$(Get-Date)]"
	}
	
} #EndFunction Compare-VMHost

Function Move-Template2Datastore
{
	
<#
.SYNOPSIS
	Invoke SVMotion for VM Templates.
.DESCRIPTION
	The Move-Template2Datastore cmdlet invokes Storage vMotion task for VM Template(s).
.PARAMETER Template
	VM Template object(s), returned by `Get-Template` cmdlet.
.PARAMETER Datastore
	Target Datastore object, returned by `Get-Datastore` cmdlet.
.EXAMPLE
	PS C:\> Get-Template 'rhel*' |Move-Template2Datastore (Get-Datastore $DatastoreName)
.EXAMPLE
	PS C:\> (Get-Template).Where{$_.ExtensionData.Guest.GuestId -match '^windows'} |Move-Template2Datastore -DatastoreCluster $DatastoreClusterName
	Distribute all Windows Guest based templates to randomly choisen Datastores in a DatastoreCluster.
.EXAMPLE
	PS C:\> Get-Template |? {($_.DatastoreIdList |% {(Get-View -Id ($_)).Name}) -contains $DatastoreNameSource} |Move-Template2Datastore (Get-Datastore $DatastoreNameTarget)
	Find all templates that reside on particular (source) Datastore and move them to another (target) Datastore.
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0/5.1|PowerCLi 6.5
	Platform    :: Tested on vSphere 5.5/6.0|VCenter 5.5U2/VCSA 6.0U1
	Requirement :: ESXi Hosts where Templates are registered must be HA/DRS Cluster members. PowerShell 3.0+
	Version 1.0 :: 14-Dec-2016 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2016/12/19/migrate-vm-template-powercli
#>
	
	[CmdletBinding(DefaultParameterSetName = 'DS')]
	[Alias("Move-ViMTemplate2Datastore")]
	[OutputType([PSCustomObject])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Alias("VMTemplate", "Templates")]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.Template[]]$Template
		 ,
		[Parameter(Mandatory, Position = 0, ParameterSetName = 'DS')]
		$Datastore
		 ,
		[Parameter(Mandatory, Position = 0, ParameterSetName = 'DSC')]
		[VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.DatastoreCluster]$DatastoreCluster
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		If ($PSCmdlet.ParameterSetName -eq 'DS')
		{
			If ($Datastore -isnot [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.VmfsDatastore] `
				-and $Datastore -isnot [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.NasDatastore]) { Throw "Unsupported Datastore type" }
		}
	} #EndBegin
	
	Process
	{
		Try
		{
			$null = . {
				
				### Get random Datastore from the DatastoreCluster ###
				If ($PSCmdlet.ParameterSetName -eq 'DSC')
				{
					$Datastore = Get-DatastoreCluster $DatastoreCluster | Get-Datastore | sort { Get-Random } | select -First 1
				}
				
				### Convert the Template to a VM ###
				$poolMoref = (Get-ResourcePool -Location (Get-VMHost -Id $Template.HostId | Get-Cluster) -Name Resources).Id
				$hostMoref = $Template.HostId
				$ViewTemplate = Get-View -VIObject $Template
				$ViewTemplate.MarkAsVirtualMachine($poolMoref, $hostMoref)
				$VM = Get-VM -Name $Template.Name
				
				### Initialize SVMotion Task ###
				$ViewVM = Get-View -VIObject $VM
				$spec = New-Object -TypeName 'VMware.Vim.VirtualMachineRelocateSpec'
				$spec.Datastore = New-Object -TypeName 'VMware.Vim.ManagedObjectReference'
				$spec.Datastore = $Datastore.Id
				$priority = [VMware.Vim.VirtualMachineMovePriority]'defaultPriority'
				$TaskMoref = $ViewVM.RelocateVM_Task($spec, $priority)
				
				$ViewTask = Get-View $TaskMoref
				For ($i = 1; $i -lt [int32]::MaxValue; $i++)
				{
					If ("running", "queued" -contains $ViewTask.Info.State)
					{
						$ViewTask.UpdateViewData("Info")
						If ($ViewTask.Info.Progress -ne $null)
						{
							Write-Progress -Activity "Migrating Template ..." -Status "Template [$($VM.Name)]" `
										   -CurrentOperation "Datastore [$($Datastore.Name)]" `
										   -PercentComplete $ViewTask.Info.Progress -ErrorAction SilentlyContinue
							Start-Sleep -Seconds 3
						}
					}
					Else { Write-Progress -Activity "Completed" -Completed; Break }
				}
				If ($ViewTask.Info.State -eq "error")
				{
					$ViewTask.UpdateViewData("Info.Error")
					$ViewTask.Info.Error.Fault.FaultMessage | % { $_.Message }
				}
				
				### Convert the VM back to the Template ###
				$ViewVM.MarkAsTemplate()
				
				$ErrorMsg = $null
			}
		}
		Catch { $ErrorMsg = "{0}" -f $Error.Exception.Message }
		
		$Properties = [ordered]@{
			Template = $Template.Name
			Datastore = $Datastore.Name
			Error = $ErrorMsg
		}
		$Object = New-Object PSObject -Property $Properties
		$Object
		
	} #EndProcess
	
	End { }
	
} #EndFunction Move-Template2Datastore

Function Read-VMHostCredential
{
	
<#
.SYNOPSIS
	Decrypt an encrypted file.
.DESCRIPTION
	The Read-VMHostCredential cmdlet decrypts an encrypted file, created by `New-SecureCred.ps1` script.
.PARAMETER CredFile
	Full path to an encrypted file.
.PARAMETER User
	Returns username and not a password.
.EXAMPLE
	PS C:\> Read-VMHostCredential "$($env:USERPROFILE)\Documents\esx.sec"
	Decrypts the password from the default file.
.EXAMPLE
	PS C:\> Read-VMHostCredential -User
	Returns user name.
.NOTES
	Author      :: Roman Gelman @rgelman75
	Requirement :: PowerShell 3.0+
	Version 1.0 :: 27-Dec-2016 :: [Release] :: Publicly available
.LINK
	https://github.com/rgel/Azure/blob/master/New-SecureCred.ps1
#>
	
	Param (
		[Parameter(Mandatory = $false, Position = 0)]
		[ValidateNotNullorEmpty()]
		[ValidateScript({ Test-Path $_ -PathType Leaf })]
		[string]$CredFile = "$(Split-Path $PROFILE)\esx.cred"
		 ,
		[Parameter(Mandatory = $false)]
		[switch]$User
	)
	
	$Login = 'root'
	
	If (Test-Path $CredFile -PathType Leaf)
	{
		$SecurePwd = gc $CredFile | ConvertTo-SecureString
		Try
		{
			$immCred = New-Object -TypeName 'System.Management.Automation.PSCredential'($Login, $SecurePwd) -EA Stop
			If ($User) { return $Login }
			Else { return $immCred.GetNetworkCredential().Password }
		}
		Catch { return $null }
	}
	Else { return $null }
	
} #EndFunction Read-VMHostCredential

Function Connect-VMHostPutty
{
	
<#
.SYNOPSIS
	Connect to an ESXi host by putty SSH client.
.DESCRIPTION
	The Connect-VMHostPutty cmdlet runs `putty.exe` from the PowerShell console
	and opens SSH connection(s) to the ESXi host(s) with no password prompt.
.PARAMETER VMHost
	ESXi hostname or IP address.
.PARAMETER PuttyExec
	'putty.exe' executable full path.
.EXAMPLE
	PS C:\> putty esx1
.EXAMPLE
	PS C:\> 1..9 |% {putty "esx$_"}
	Open multiple connections, usable to connect to all HA/DRS cluster hosts.
.NOTES
	Author      :: Roman Gelman @rgelman75
	Requirement :: PowerShell 3.0+
	Version 1.0 :: 27-Dec-2016 :: [Release] :: Publicly available
	Version 1.1 :: 04-Jan-2017 :: [Bugfix]  :: The `putty` Alias was not created during Module import
	
.LINK
	https://ps1code.com/2016/12/27/esxi-powershell-and-putty
#>
	
	[Alias("Connect-ViMVMHostPutty", "putty")]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$VMHost
		 ,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[ValidateScript({ Test-Path $_ -PathType Leaf })]
		[string]$PuttyExec = "$(Split-Path $PROFILE)\putty.exe"
	)
	
	$PuttyPwd = Read-VMHostCredential
	$PuttyLogin = Read-VMHostCredential -User
	If ($PuttyPwd) { &$PuttyExec -ssh $PuttyLogin@$VMHost -pw $PuttyPwd }
	
} #EndFunction Connect-VMHostPutty

Function Set-MaxSnapshotNumber
{
	
<#
.SYNOPSIS
	Set maximum allowed snapshots.
.DESCRIPTION
	The Set-MaxSnapshotNumber cmdlet sets maximum allowed VM(s) snapshots.
.PARAMETER VM
	VM object(s), returnd by `Get-VM` cmdlet.
.PARAMETER Number
	Specifies maximum allowed snapshot number.
	Allowed values are [0 - 496].
.PARAMETER Report
	Do not edit anything, report only.
.EXAMPLE
	PS C:\> Get-VM $VMName |Set-MaxSnapshotNumber
	Set default value.
.EXAMPLE
	PS C:\> Get-VM |Set-MaxSnapshotNumber -Report
	Get current set value for all VM in the inventory.
.EXAMPLE
	PS C:\> Get-VM |Set-MaxSnapshotNumber -Report |? {$_.MaxSnapshot -eq 0}
	Get VM with snapshots prohibited.
.EXAMPLE
	PS C:\> Get-VM $VMName |Set-MaxSnapshotNumber -Number 496
	Set maximum supported value.
.EXAMPLE
	PS C:\> Get-VM |? {$_.Name -like 'win*'} |Set-MaxSnapshotNumber 0 -Confirm:$false
	Prohibit snapshots for multiple VM without confirmation.
.NOTES
	Idea        :: William Lam
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0|PowerCLi 6.5
	Platform    :: Tested on vSphere 5.5/6.0|VCenter 5.5U2/VCSA 6.0U1
	Requirement :: PowerShell 3.0+
	Version 1.0 :: 24-Jan-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2017/01/24/max-snap-powercli
#>
	
	[CmdletBinding(DefaultParameterSetName = "SET", ConfirmImpact = 'High', SupportsShouldProcess = $true)]
	[Alias("Set-ViMMaxSnapshotNumber", "maxsnap")]
	[OutputType([PSCustomObject])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$VM
		 ,
		[Parameter(Mandatory = $false, Position = 0, ParameterSetName = 'SET')]
		[ValidateRange(0, 496)]
		[Alias("Quantity")]
		[uint16]$Number = 31
		 ,
		[Parameter(Mandatory, Position = 0, ParameterSetName = 'GET')]
		[Alias("ReportOnly")]
		[switch]$Report
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$WarningPreference = 'SilentlyContinue'
		$AdvSetting = 'snapshot.maxSnapshots'
		$NotSetValue = 'NotSet'
	} #EndBegin
	
	Process
	{
		
		$ShouldMessage = Switch ($Number)
		{
			31      { "Set maximum allowed snapshot number to the default [$Number]"; Break }
			0       { "Prohibit taking snapshots at all!"; Break }
			496     { "Set maximum allowed snapshot number to the maximum possible [$Number]"; Break }
			Default { "Set maximum allowed snapshot number to [$Number]" }
		}
		
		If ($PSCmdlet.ParameterSetName -eq 'SET')
		{
			
			If ($PSCmdlet.ShouldProcess($VM.Name, $ShouldMessage))
			{
				Try
				{
					$AdvancedSettingImplBefore = $VM | Get-AdvancedSetting -Name $AdvSetting
					$CurrentSetting = If ($AdvancedSettingImplBefore) { $AdvancedSettingImplBefore.Value }
					Else { $NotSetValue }
					$AdvancedSettingImplAfter = $VM | New-AdvancedSetting -Name $AdvSetting -Value $Number -Force -Confirm:$false
					$Properties = [ordered]@{
						VM = $VM.Name
						AdvancedSetting = $AdvSetting
						PreviousValue = $CurrentSetting
						CurrentValue = $AdvancedSettingImplAfter.Value
					}
					$Object = New-Object PSObject -Property $Properties
					$Object
				}
				Catch { "{0}" -f $Error.Exception.Message }
			}
		}
		Else
		{
			
			Try
			{
				$AdvancedSettingImplBefore = $VM | Get-AdvancedSetting -Name $AdvSetting
				$CurrentSetting = If ($AdvancedSettingImplBefore) { $AdvancedSettingImplBefore.Value }
				Else { $NotSetValue }
				$Properties = [ordered]@{
					VM = $VM.Name
					MaxSnapshot = $CurrentSetting
				}
				$Object = New-Object PSObject -Property $Properties
				$Object
			}
			Catch { "{0}" -f $Error.Exception.Message }
		}
	} #EndProcess
	
	End { }
	
} #EndFunction Set-MaxSnapshotNumber

Filter Convert-MoRef2Name
{
	
<#
.SYNOPSIS
	Convert a MoRef number to the Name.
.DESCRIPTION
	This filter converts VI object's MoRef number to VI object's Name.
.PARAMETER MoRef
	VI [M]anaged [o]bject [ref]erence number.
.PARAMETER ShortName
	Truncate the full object name if possible.
.EXAMPLE
	PS C:\> Get-VMHost 'esx1.*' |select Name,@{N='Cluster';E={$_.ParentId |Convert-MoRef2Name}}
	Get VMHost's parent container name from VMHosts's property `ParentId`.
	It may be HA/DRS cluster name, Datacenter name or Folder name.
.EXAMPLE
	PS C:\> Get-VDSwitch |select Name,@{N='Portgroups';E={'[ ' + ((($_ |select -expand ExtensionData).Portgroup |Convert-MoRef2Name |sort) -join ' ][ ') + ' ]'}}
	Expand all! Portgroup names from Distributed VSwitch's property `ExtensionData.Portgroup`.
.EXAMPLE
	PS C:\> Get-Datastore 'test*' |sort Name |select Name,@{N='ConnectedHosts';E={'[' + ((($_ |select -expand ExtensionData).Host.Key |Convert-MoRef2Name -ShortName |sort) -join '] [') + ']' }}
	Expand all connected VMHost names from Datastore's property `ExtensionData.Host.Key`.
	Truncate VMHost's hostname from FQDN if it is possible.
.INPUTS
	[System.String] VI Object Id/MoRef.
.OUTPUTS
	[System.String] VI Object name.
.NOTES
	Author      :: Roman Gelman @rgelman75
	Version 1.0 :: 09-Sep-2016 :: [Release] :: Publicly available
	Version 1.1 :: 18-Apr-2017 :: [Change]  :: Empty string returned on error
.LINK
	https://ps1code.com
#>
	
	Param (
		[string]$MoRef,
		[switch]$ShortName
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
	}
	
	Process
	{
		Try
		{
			$Name = (Get-View -Id $_).Name
			If ($ShortName) { $Name = [regex]::Match($Name, '^(.+?)(\.|$)').Groups[1].Value }
		}
		Catch { $Name = '' }
		return $Name
	}
	
} #EndFilter Convert-MoRef2Name

Function Get-VMHostGPU
{
	
<#
.SYNOPSIS
	Get ESXi hosts' GPU info.
.DESCRIPTION
	The Get-VMHostGPU cmdlet gets GPU info for ESXi host(s).
.PARAMETER VMHost
	VMHost object(s), returnd by Get-VMHost cmdlet.
.EXAMPLE
	PowerCLI C:\> Get-VMHost $VMHostName |Get-VMHostGPU
.EXAMPLE
	PowerCLI C:\> Get-Cluster $vCluster |Get-VMHost |Get-VMHostGPU |ft -au
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0|PowerCLi 6.5
	Platform    :: Tested on vSphere 5.5/6.5|vCenter 5.5U2/VCSA 6.5a|NVIDIAGRID K2
	Requirement :: PowerShell 3.0+
	Version 1.0 :: 23-Apr-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2017/04/23/esxi-vgpu-powercli
#>
	
	[Alias("Get-ViMVMHostGPU", "esxgpu")]
	[CmdletBinding()]
	[OutputType([PSCustomObject])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$WarningPreference = 'SilentlyContinue'
		$rgxSuffix = '^grid_'
	} #EndBegin
	
	Process
	{
		$VMHostView = Get-View -Id $VMHost.Id -Verbose:$false
		
		$Profiles = $VMHostView.Config.SharedPassthruGpuTypes
		
		foreach ($GraphicInfo in $VMHostView.Config.GraphicsInfo)
		{
			$VMs = @()
			$VMs += foreach ($vGpuVm in $GraphicInfo.Vm) { $vGpuVm | Convert-MoRef2Name }
			
			if ($VMs)
			{
				foreach ($VM in (Get-VM $VMs | ? { $_.PowerState -eq 'PoweredOn' }))
				{
					$ProfileActive = ($VM.ExtensionData.Config.Hardware.Device | ? { $_.Backing.Vgpu } |
						select @{ N = 'Profile'; E = { $_.Backing.Vgpu -replace $rgxSuffix, '' } } | select -First 1).Profile
				}
			}
			else
			{
				$ProfileActive = 'N/A'
			}
			$returnGraphInfo = [pscustomobject]@{
				VMHost = [regex]::Match($VMHost.Name, '^(.+?)(\.|$)').Groups[1].Value
				VideoCard = $GraphicInfo.DeviceName
				Vendor = $GraphicInfo.VendorName
				Mode = $GraphicInfo.GraphicsType
				MemoryGB = [System.Math]::Round($GraphicInfo.MemorySizeInKB/1MB, 0)
				ProfileSupported = ($Profiles -replace $rgxSuffix, '') -join ','
				ProfileActive = $ProfileActive
				VM = $VMs
			}
			$returnGraphInfo
		}
		
	} #EndProcess
	
	End { }
	
} #EndFunction Get-VMHostGPU

Function Test-VMPing
{
	
<#
.SYNOPSIS
	Test VMware VM accessibility.
.DESCRIPTION
	This function tests Powered on VMware VM guest accessibility by ping.
.PARAMETER VM
	Specifies VM object(s), returned by Get-VM cmdlet.
.PARAMETER Restart
	If specified, try to restart not responding VM.
.EXAMPLE
	PS C:\> Get-VM vm1,vm2 |Test-VMPing
.EXAMPLE
	PS C:\> Get-Cluster PROD |Get-VM |sort Name |Test-VMPing |? {!$_.Responding} |ft -au
	Get all not responding VM in a cluster.
.EXAMPLE
	PS C:\> Get-VM |Test-VMPing -Restart -Confirm:$true
	Restart all not responding VM with confirmation.
.EXAMPLE
	PS C:\> Get-VM |Test-VMPing -Verbose |Export-Csv -NoTypeInformation .\Ping.csv -Encoding UTF8
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0|PowerCLi 6.5.1
	Platform    :: Tested on vSphere 5.5/6.5|VCenter 5.5U2/VCSA 6.5
	Requirement :: PowerShell 3.0
	Version 1.0 :: 16-May-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2017/05/23/test-vm-hotfix
#>
	
	[Alias("tvmp", "Test-ViMVMPing")]
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	Param (
		[Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$VM
		 ,
		[Parameter(Mandatory = $false)]
		[switch]$Restart
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$StatVM = 0
		$StatPoweredVM = 0
		$StatNoPingVM = 0
		Write-Verbose "Test-VMPing started at $(Get-Date)"
	}
	Process
	{
		$StatVM += 1
		if ($VM.PowerState -eq 'PoweredOn')
		{
			$StatPoweredVM += 1
			Try
			{
				$VMGuestHostname = if ('localhost', $null -notcontains $VM.Guest.HostName) { $VM.Guest.HostName }
				else { $VM.Name }
				Write-Progress -Activity 'Test-VMPing' -Status 'In progress ...' -CurrentOperation "VM [$($VM.Name)] - Hostname [$VMGuestHostname]"
				Test-Connection -ComputerName $VMGuestHostname -Count 1 | Out-Null
				[pscustomobject] @{
					VM = $VM.Name
					Hostname = $VMGuestHostname
					GuestOS = $VM.Guest.OSFullName
					Notes = $VM.Notes
					Responding = $true
				}
			}
			Catch
			{
				$StatNoPingVM += 1
				if ($PSBoundParameters.ContainsKey('Restart'))
				{
					if ($VM.Guest.ExtensionData.ToolsRunningStatus -eq 'guestToolsRunning') { $VM | Restart-VMGuest }
					else { $VM | Restart-VM }
				}
				else
				{
					[pscustomobject] @{
						VM = $VM.Name
						Hostname = $VMGuestHostname
						GuestOS = $VM.Guest.OSFullName
						Notes = $VM.Notes
						Responding = $false
					}
				}
			}
		}
	}
	End
	{
		Write-Verbose "Test-VMPing finished at $(Get-Date)"
		Write-Verbose "Test-VMPing Statistic: Total VM: [$StatVM], Powered On: [$StatPoweredVM], Not Responding: [$StatNoPingVM]"
	}
	
} #EndFunction Test-VMPing

Function Test-VMHotfix
{
	
<#
.SYNOPSIS
	Test VMware VM for installed Hotfixes.
.DESCRIPTION
	This function tests Powered on Windows based
	VMware VM guest(s) for installed Hotfix(es)/Patch(es).
.PARAMETER VM
	Specifies VM object(s), returned by Get-VM cmdlet.
.PARAMETER KB
	Specifies HotfixID pattern.
	May contain 'kb' suffix, any digits, asterisk '*' or question mark '?' symbol.
.EXAMPLE
	PS C:\> Get-VM vm1,vm2 |Test-VMHotfix -KB 'kb4012???'
.EXAMPLE
	PS C:\> Get-VM |Test-VMHotfix 'kb40122*'
.EXAMPLE
	PS C:\> Get-Cluster PROD |Get-VM |sort Name |Test-VMHotfix -KB 'kb4012???' -Verbose |epcsv .\MS17-010.csv -Encoding UTF8 -notype
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0|PowerCLi 6.5.1
	Platform    :: Tested on vSphere 5.5/6.5|VCenter 5.5U2/VCSA 6.5
	Requirement :: PowerShell 4.0
	Version 1.0 :: 16-May-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2017/05/23/test-vm-hotfix
#>
	
	[Alias("tvmkb", "Test-ViMVMHotfix")]
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$VM
		 ,
		[Parameter(Mandatory, Position = 0)]
		[Alias("Hotfix", "Patch")]
		[string]$KB
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$StatVM = 0
		$StatPoweredVM = 0
		$StatNoHotfix = 0
		$StatNotRespondVM = 0
		Write-Verbose "Test-VMHotfix started at $(Get-Date)"
	}
	Process
	{
		$StatVM += 1
		if ($VM.PowerState -eq 'PoweredOn' -and $VM.Guest -match 'Microsoft')
		{
			$StatPoweredVM += 1
			Try
			{
				$VMGuestHostname = if ('localhost', $null -notcontains $VM.Guest.HostName) { $VM.Guest.HostName }
				else { $VM.Name }
				Write-Progress -Activity 'Test-VMHotfix' -Status "Looking for KB like [$KB] ..." -CurrentOperation "VM [$($VM.Name)] - Hostname [$VMGuestHostname]"
				$KBs = (Get-HotFix -ComputerName $VMGuestHostname).Where{ $_.HotFixID -like $KB }
				
				if ($KBs)
				{
					foreach ($MatchedKB in $KBs)
					{
						[pscustomobject] @{
							VM = $VM.Name
							Notes = $VM.Notes
							GuestOS = $VM.Guest.OSFullName
							Hotfix = $MatchedKB.HotFixID
						}
					}
				}
				else
				{
					$StatNoHotfix += 1
					[pscustomobject] @{
						VM = $VM.Name
						Notes = $VM.Notes
						GuestOS = $VM.Guest.OSFullName
						Hotfix = ''
					}
				}
			}
			Catch
			{
				$StatNotRespondVM += 1
				[pscustomobject] @{
					VM = $VM.Name
					Notes = $VM.Notes
					GuestOS = $VM.Guest.OSFullName
					Hotfix = 'Unknown'
				}
			}
		}
	}
	End
	{
		Write-Verbose "Test-VMHotfix finished at $(Get-Date)"
		Write-Verbose "Test-VMHotfix Statistic: Total VM: [$StatVM], Powered On: [$StatPoweredVM], No Hotfix: [$StatNoHotfix], Not Responding: [$StatNotRespondVM]"
	}
	
} #EndFunction Test-VMHotfix

Function Get-VMHostPnic
{
	
<#
.SYNOPSIS
	Get VMHost PNIC(s).
.DESCRIPTION
	This function gets VMHost physical NIC (Network Interface Card) info.
.PARAMETER VMHost
	Specifies ESXi host object(s), returned by Get-VMHost cmdlet.
.PARAMETER SpeedMbps
	If specified, only vmnics that match this link speed are returned.
.PARAMETER Vendor
	If specified, only vmnics from this vendor are returned.
.EXAMPLE
	PS C:\> Get-VMHost |sort Name |Get-VMHostPnic -Verbose |? {$_.SpeedMbps} |epcsv -notype .\NIC.csv
	Export connected NICs only.
.EXAMPLE
	PS C:\> Get-Cluster PROD |Get-VMHost -State Connected |Get-VMHostPnic |? {1..999 -contains $_.SpeedMbps} |ft -au
	Get all connected VMHost NICs with link speed lower than 1Gb.
.EXAMPLE
	PS C:\> Get-VMHost 'esxdmz[1-9].*' |sort Name |Get-VMHostPnic -Vendor Emulex, HPE |Format-Table -AutoSize
	Get vendor specific NICs only.
.EXAMPLE
	PS C:\> Get-Cluster PROD |Get-VMHost |Get-VMHostPnic -SpeedMbps 10000} |group VMHost |sort Name |select Name, Count, @{N='vmnic';E={($_ |select -expand Group).PNIC}}
	Get all 10Gb VMHost NICs in a cluster, group by VMHost.
.EXAMPLE
	PS C:\> Get-VMHost |sort Parent, Name |Get-VMHostPnic -SpeedMbps 0 |group VMHost |select Name, Count, @{N='vmnic';E={(($_ |select -expand Group).PNIC) -join ', '}}
	Get all connected VMHost NICs in an Inventory, group by VMHost and sort by Cluster.
.EXAMPLE
	PS C:\> Get-VMHost 'esxprd1.*' |Get-VMHostPnic -Verbose
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5.2
	Platform    :: Tested on vSphere 5.5/6.5 | VCenter 5.5U2/VCSA 6.5U1
	Requirement :: PowerShell 3.0
	Version 1.0 :: 15-Jun-2017 :: [Release] :: Publicly available
	Version 1.1 :: 12-Nov-2017 :: [Improvement] :: Added properties: vSphere, DriverVersion, Firmware
	Version 1.2 :: 13-Nov-2017 :: [Change] :: The -Nolink parameter replaced with two new parameters -SpeedMbps and -Vendor
.LINK
	https://ps1code.com/2017/06/18/esxi-peripheral-devices-powercli
#>
	
	[CmdletBinding()]
	[Alias("Get-ViMVMHostPnic", "esxnic")]
	[OutputType([PSCustomObject])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost
		 ,
		[Parameter(Mandatory = $false)]
		[uint32]$SpeedMbps
		 ,
		[Parameter(Mandatory = $false)]
		[ValidateSet('Emulex', 'Intel', 'Broadcom', 'HPE', 'Unknown', IgnoreCase = $true)]
		[string[]]$Vendor
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$WarningPreference = 'SilentlyContinue'
		$StatVMHost = 0
		$Statvmnic = 0
		$StatBMC = 0
		$StatDown = 0
		$FunctionName = '{0}' -f $MyInvocation.MyCommand
		Write-Verbose "$FunctionName started at [$(Get-Date)]"
	}
	Process
	{
		Try
		{
			$StatVMHost += 1
			$PNICs = ($VMHost | Get-View -Verbose:$false).Config.Network.Pnic
			$esxcli = Get-EsxCli -VMHost $VMHost.Name -V2 -Verbose:$false
			$vSphere = $esxcli.system.version.get.Invoke()
			
			foreach ($Pnic in $PNICs)
			{
				Write-Progress -Activity $FunctionName -Status "VMHost [$($VMHost.Name)]" -CurrentOperation "PNIC [$($Pnic.Device)]"
				
				if ($Pnic.Device -match 'vmnic')
				{
					$Statvmnic += 1
					$NicVendor = switch -regex ($Pnic.Driver)
					{
						'^(elx|be)' { 'Emulex'; Break }
						'^(igb|ixgb|e10)' { 'Intel'; Break }
						'^(bnx|tg|ntg)' { 'Broadcom'; Break }
						'^nmlx' { 'HPE' }
						Default { 'Unknown' }
					}
					
					$NicInfo = $esxcli.network.nic.get.Invoke(@{ nicname = "$($Pnic.Device)" })
					
					$res = [pscustomobject] @{
						VMHost = $VMHost.Name
						vSphere = "$([regex]::Match($vSphere.Version, '^\d\.\d').Value)U$($vSphere.Update)$([regex]::Match($vSphere.Build, '-\d+').Value)"
						PNIC = $Pnic.Device
						MAC = ($Pnic.Mac).ToUpper()
						SpeedMbps = if ($Pnic.LinkSpeed.SpeedMb) { $Pnic.LinkSpeed.SpeedMb } else { 0 }
						Vendor = $NicVendor
						Driver = $Pnic.Driver
						DriverVersion = $NicInfo.DriverInfo.Version
						Firmware = $NicInfo.DriverInfo.FirmwareVersion
					}
					
					if (!$res.SpeedMbps) { $StatDown += 1 }
					
					### Return output ###
					$Next = if ($PSBoundParameters.ContainsKey('SpeedMbps')) { if ($res.SpeedMbps -eq $SpeedMbps) { $true }
						else { $false } }
					else { $true }
					if ($Next) { if ($PSBoundParameters.ContainsKey('Vendor')) { if ($Vendor -icontains $res.Vendor) { $res } }
						else { $res } }
				}
				else
				{
					$StatBMC += 1
				}
			}
		}
		Catch
		{
			"{0}" -f $Error.Exception.Message
		}
	}
	End
	{
		Write-Progress -Activity "Completed" -Completed
		Write-Verbose "$FunctionName finished at [$(Get-Date)]"
		Write-Verbose "$FunctionName Statistic: Total VMHost: [$StatVMHost], Total vmnic: [$Statvmnic], Down: [$StatDown], BMC: [$StatBMC]"
	}
	
} #EndFunction Get-VMHostPnic

Function Get-VMHostHba
{
	
<#
.SYNOPSIS
	Get VMHost Fibre Channel HBA.
.DESCRIPTION
	This function gets VMHost Fibre Channel Host Bus Adapter info.
.PARAMETER VMHost
	Specifies ESXi host object(s), returned by Get-VMHost cmdlet.
.PARAMETER Nolink
	If specified, only disconnected adapters returned.
.PARAMETER FormatWWN
	Specifies how to format WWN property.
.EXAMPLE
	PS C:\> Get-VMHost |sort Name |Get-VMHostHba -Verbose |? {$_.SpeedGbps} |epcsv -notype .\HBA.csv
	Export connected HBAs only.
.EXAMPLE
	PS C:\> Get-Cluster PROD |Get-VMHost -State Connected |Get-VMHostHba |? {$_.SpeedGbps -gt 4} |ft -au
	Get all connected VMHost HBAs with link speed greater than 4Gbps.
.EXAMPLE
	PS C:\> Get-VMHost 'esxdmz[1-9].*' |sort Name |Get-VMHostHba -Nolink |Format-Table -AutoSize
	Get disconnected HBAs only.
.EXAMPLE
	PS C:\> Get-Cluster PROD |Get-VMHost |Get-VMHostHba |? {$_.SpeedGbps -eq 8} |group VMHost |sort Name |select Name, Count, @{N='vmhba';E={($_ |select -expand Group).HBA}}
	Get all 8Gb VMHost HBAs in a cluster, group by VMHost.
.EXAMPLE
	PS C:\> Get-VMHost |sort Parent, Name |Get-VMHostHba |? {$_.SpeedGbps} |group VMHost |select Name, Count, @{N='vmhba';E={(($_ |select -expand Group).HBA) -join ', '}}
	Get all connected VMHost HBAs in an Inventory, group by VMHost and sort by Cluster.
.EXAMPLE
	PS C:\> Get-VMHost 'esxprd1.*' |Get-VMHostHba
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0|PowerCLi 6.5.1
	Platform    :: Tested on vSphere 5.5/6.5|VCenter 5.5U2/VCSA 6.5
	Requirement :: PowerShell 3.0
	Version 1.0 :: 15-Jun-2017 :: [Release] :: Publicly available
	Version 1.1 :: 13-Nov-2017 :: [Improvement] :: Added property vSphere
.LINK
	https://ps1code.com/2017/06/18/esxi-peripheral-devices-powercli
#>
	
	[CmdletBinding()]
	[Alias("Get-ViMVMHostHba", "esxhba")]
	[OutputType([PSCustomObject])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost
		 ,
		[Parameter(Mandatory = $false)]
		[Alias("Down")]
		[switch]$Nolink
		 ,
		[Parameter(Mandatory = $false, Position = 0)]
		[ValidateSet('XX:XX:XX:XX:XX:XX:XX:XX', 'xx:xx:xx:xx:xx:xx:xx:xx',
					 'XXXXXXXXXXXXXXXX', 'xxxxxxxxxxxxxxxx')]
		[string]$FormatWWN = 'XX:XX:XX:XX:XX:XX:XX:XX'
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$WarningPreference = 'SilentlyContinue'
		$StatVMHost = 0
		$StatHba = 0
		$StatDown = 0
		
		switch -casesensitive -regex ($FormatWWN)
		{
			'^xxx' { $WwnCase = 'x'; $WwnColon = $false; Break }
			'^xx:' { $WwnCase = 'x'; $WwnColon = $true; Break }
			'^XXX' { $WwnCase = 'X'; $WwnColon = $false; Break }
			'^XX:' { $WwnCase = 'X'; $WwnColon = $true }
		}
		
		$FunctionName = '{0}' -f $MyInvocation.MyCommand
		Write-Verbose "$FunctionName started at [$(Get-Date)]"
	}
	Process
	{
		Try
		{
			$StatVMHost += 1
			$HBAs = ($VMHost | Get-View -Verbose:$false).Config.StorageDevice.HostBusAdapter
			$esxcli = Get-EsxCli -VMHost $VMHost.Name -V2 -Verbose:$false
			$vSphere = $esxcli.system.version.get.Invoke()
			
			foreach ($Hba in $HBAs)
			{
				Write-Progress -Activity $FunctionName -Status "VMHost [$($VMHost.Name)]" -CurrentOperation "HBA [$($Hba.Device)]"
				
				if ($Hba.PortWorldWideName)
				{
					$StatHba += 1
					### WWN ###
					$WWN = "{0:$WwnCase}" -f $Hba.PortWorldWideName
					if ($WwnColon) { $WWN = $WWN -split '(.{2})' -join ':' -replace ('(^:|:$)', '') -replace (':{2}', ':') }
					### Vendor ###
					$Vendor = switch -regex ($Hba.Driver)
					{
						'^lp' { 'Emulex'; Break }
						'^ql' { 'QLogic'; Break }
						'^b(f|n)a' { 'Brocade'; Break }
						'^aic' { 'Adaptec'; Break }
						Default { 'Unknown' }
					}
					
					$res = [pscustomobject] @{
						VMHost = $VMHost.Name
						vSphere = "$([regex]::Match($vSphere.Version, '^\d\.\d').Value)U$($vSphere.Update)$([regex]::Match($vSphere.Build, '-\d+').Value)"
						HBA = $Hba.Device
						WWN = $WWN
						SpeedGbps = $Hba.Speed
						Vendor = $Vendor
						Model = [regex]::Match($Hba.Model, '^.+\d+Gb').Value
						Driver = $Hba.Driver
					}
					if (!$res.SpeedGbps) { $StatDown += 1 }
					
					if ($Nolink) { if (!($res.SpeedGbps)) { $res } }
					else { $res }
				}
			}
		}
		Catch
		{
			"{0}" -f $Error.Exception.Message
		}
	}
	End
	{
		Write-Progress -Activity "Completed" -Completed
		Write-Verbose "$FunctionName finished at [$(Get-Date)]"
		Write-Verbose "$FunctionName Statistic: Total VMHost: [$StatVMHost], Total HBA: [$StatHba], Down: [$StatDown]"
	}
	
} #EndFunction Get-VMHostHba

Function Convert-VI2PSCredential
{
	
<#
.SYNOPSIS
	Convert VICredentialStoreItem object to PSCredential.
.DESCRIPTION
	This function converts [VICredentialStoreItem] object to [PSCredential] data type
	for using it as value of [-Credential] parameter in any cmdlets.
.PARAMETER VICredentialStoreItem
	Specifies VI Credential Store Item(s), returned by Get-VICredentialStoreItem cmdlet.
.EXAMPLE
	PS C:\> Get-VICredentialStoreItem -Host xclarity | Convert-VI2PSCredential
.EXAMPLE
	PS C:\> Get-VICredentialStoreItem | Convert-VI2PSCredential | select UserName, @{N='ClearTextPassword'; E={$_.GetNetworkCredential().Password}}
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5.2
	Requirement :: PowerShell 3.0
	Version 1.0 :: 17-Aug-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/category/vmware-powercli/vi-module/
#>
	
	[CmdletBinding()]
	[Alias("Convert-ViMVI2PSCredential", "vi2ps")]
	[OutputType([System.Management.Automation.PSCredential])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VMware.VimAutomation.ViCore.Types.V1.VICredentialStoreItem]$VICredentialStoreItem
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$WarningPreference = 'SilentlyContinue'
	}
	Process
	{
		Try
		{
			$UserName = $VICredentialStoreItem.User
			$Password = ConvertTo-SecureString $VICredentialStoreItem.Password -AsPlainText -Force
			return New-Object System.Management.Automation.PSCredential($UserName, $Password)
		}
		Catch
		{
			"{0}" -f $Error.Exception.Message
		}
	}
	End { }
	
} #EndFunction Convert-VI2PSCredential

Function Get-VMGuestPartition
{
	
<#
.SYNOPSIS
	Get VM guest partition usage.
.DESCRIPTION
	This function retrieves VM guest partition usage.
.PARAMETER VM
	Specifies VM object(s), returned by Get-VM cmdlet.
.EXAMPLE
	PS C:\> Get-VM vm1, vm2 |Get-VMGuestPartition
.EXAMPLE
	PS C:\> Get-VM |? {$_.Guest.GuestFamily -like 'win*'} |Get-VMGuestPartition |sort VM, Volume |ogv -Title 'Windows VM Partition Usage Report'
	Get report in a GridView control for Microsoft Windows guests only.
.EXAMPLE
	PS C:\> Get-Cluster DEV |Get-VM |Get-VMGuestPartition |? {$_.'Usage%' -gt 90} |sort 'Usage%' -Descending |ft -au
.EXAMPLE
	PS C:\> Get-VM |gvmpart |epcsv '.\VMDiskUsage.csv' -notype -Encoding UTF8
	Export the report to Excel file (have to use UTF8 encoding for the correct UsageBar property representation).
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5.2
	Platform    :: Tested on vSphere 5.5/6.0/6.5 | VCenter 5.5U2/VCSA 6.0U1/VCSA 6.5
	Dependency  :: The New-PercentageBar function (included in the module)
	Requirement :: The VM(s) must be PoweredOn and VMTools must be installed and running
	Version 1.0 :: 17-Oct-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2017/10/17/extend-vm-guest-part-powercli
#>
	
	[Alias("Get-ViMVMGuestPartition", "gvmpart")]
	[OutputType([PSCustomObject])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$VM
	)
	
	Begin
	{
		$ErrorActionPreference = "SilentlyContinue"
	}
	Process
	{
		foreach ($Disk in $VM.Guest.Disks)
		{
			$DiskUsage = [Math]::Round(($Disk.Capacity - $Disk.FreeSpace)/$Disk.Capacity * 100, 2)
			
			[pscustomobject] @{
				VM = $VM.Name
				Volume = $Disk.Path
				CapacityGB = [Math]::Round($Disk.Capacity/1GB)
				CapacityMB = [Math]::Round($Disk.Capacity/1MB)
				FreeSpaceMB = [Math]::Round($Disk.FreeSpace/1MB)
				'Usage%' = $DiskUsage
				UsageBar = New-PercentageBar -Percent $DiskUsage
			}
		}
	}
	
} #EndFunction Get-VMGuestPartition

Function Expand-VMGuestPartition
{
	
<#
.SYNOPSIS
	Interactively increase a VM Hard Disk and expand VMGuest partition.
.DESCRIPTION
	This function interactively increases a VM's Hard Disk (optionally)
	and after that extends VMGuest partition.
.PARAMETER VM
	Specifies VM object(s), returned by Get-VM cmdlet.
.PARAMETER GuestUser
	Specifies VMGuest account with Administrative priviledges.
.PARAMETER GuestPassword
	Specifies VMGuest password for the account, specified by -GuestUser parameter.
.PARAMETER GuestCred
	Specifies VMGuest credentials.
.PARAMETER HostCred
	Specifies VMHost credentials.
.EXAMPLE
	PS C:\> Get-VM $VMName |Expand-VMGuestPartition -Confirm:$false -Verbose
.EXAMPLE
	PS C:\> Get-VM $VMName |Expand-VMGuestPartition -GuestPassword P@ssw0rd
.EXAMPLE
	PS C:\> Get-VM $VMName |Expand-VMGuestPartition -GuestCred (Get-VICredentialStoreItem GuestCred)
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5.2
	Platform    :: Tested on vSphere 5.5/6.0/6.5 | VCenter 5.5U2/VCSA 6.0U1/VCSA 6.5
	Requirement :: PowerShell 3.0+ | VMGuest NT6+ | VMTools running
	Dependency  :: Get-VMGuestPartition | Convert-VI2PSCredential | Write-Menu | New-PercentageBar | Start-SleepProgress (ALL included in the Vi-Module)
	Version 1.0 :: 17-Oct-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2017/10/17/extend-vm-guest-part-powercli
#>
	
	[CmdletBinding(DefaultParameterSetName = 'CREDFILE', ConfirmImpact = 'High', SupportsShouldProcess = $true)]
	[Alias("Expand-ViMVMGuestPartition", "exvmpart")]
	[OutputType([bool])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[ValidateScript({ $_.Guest.RuntimeGuestId -match '^windows[789]' })]
		[ValidateScript({ $_.Guest.ExtensionData.ToolsRunningStatus -eq 'guestToolsRunning' })]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$VM
		 ,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[VMware.VimAutomation.ViCore.Types.V1.VICredentialStoreItem]$HostCred = (Write-Menu -Menu (Get-VICredentialStoreItem) -Header "ESXi Host credentials" -Prompt "Select a VICredentialStore Item" -Shift 1 -PropertyToShow Host)
		 ,
		[Parameter(Mandatory = $false, ParameterSetName = 'CREDFILE')]
		[ValidateNotNullorEmpty()]
		[VMware.VimAutomation.ViCore.Types.V1.VICredentialStoreItem]$GuestCred = (Write-Menu -Menu (Get-VICredentialStoreItem) -Header "VM Guest credentials" -Prompt "Select a VICredentialStore Item" -Shift 1 -PropertyToShow Host)
		 ,
		[Parameter(Mandatory = $false, ParameterSetName = 'PASSWORD')]
		[ValidateNotNullorEmpty()]
		[Alias("VMGuestUser")]
		[string]$GuestUser = "Administrator"
		 ,
		[Parameter(Mandatory, ParameterSetName = 'PASSWORD')]
		[Alias("VMGuestPassword")]
		[string]$GuestPassword
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$WarningPreference = 'SilentlyContinue'
		$Steps = 3
		$MaxHddSize = 2000
		$SizeJump1 = 10
		$SizeJump2 = 50
		$SizeJump3 = 100
		$LastStep2 = 1000
	}
	Process
	{
		### Select VM HardDisk ###
		if (!($VmHdd = Get-HardDisk -VM $VM -Verbose:$false))
		{
			Throw "The VM [$($VM.Name)] has no Hard Disks!"
		}
		else
		{
			### STEP 1 ###
			$i = 1
			$SelectedHdd = Write-Menu -Menu $VmHdd -Header "Step [$i..$Steps]" -Prompt "Select VM Hard Disk to increase" -Shift 1 -AddExit
			$i++
		}
		
		if ($SelectedHdd -ne 'exit')
		{
			$Thick = If ($SelectedHdd.StorageFormat -eq 'Thick') { $true }
			else { $false }
			$Vmdk = $SelectedHdd.Filename
			$CapacityGB = [Math]::Round($SelectedHdd.CapacityGB, 0)
			
			$DatastoreName = [regex]::Match($Vmdk, '\[(?<DS>.+)\]').Groups[1].Value
			$Datastore = Get-Datastore $DatastoreName -Verbose:$false
			$DatastoreCapacityGB = $Datastore.CapacityGB
			$DatastoreFreeGB = [Math]::Round($Datastore.FreeSpaceGB, 0)
			$DatastoreUsed = $DatastoreCapacityGB - $DatastoreFreeGB
			
			[pscustomobject]@{
				VM = $VM.Name
				HardDisk = $SelectedHdd.Name
				Thick = $Thick
				CapacityGB = $CapacityGB
				Vmdk = $Vmdk
				Datastore = $DatastoreName
				DatastoreCapacityGB = $DatastoreCapacityGB
				DatastoreFreeGB = $DatastoreFreeGB
				DatastoreUsage = New-PercentageBar -MaxValue $DatastoreCapacityGB -Value $DatastoreUsed
			}
			
			### Choice desired capacity ###
			$Capacities = @()
			$OriginalCapacityGB = $CapacityGB
			$CapacityGB = ($CapacityGB/10 -as [int]) * 10
			$LastStep1 = ([Math]::Truncate(($CapacityGB + 100)/100)) * 100
			$LastSize = if ($Thick) { $CapacityGB + $DatastoreFreeGB }
			else { $MaxHddSize }
			
			### $LastSize < $LastStep1 ###
			if ($LastSize -lt $LastStep1)
			{
				for ($j = ($CapacityGB + $SizeJump1); $j -le $LastSize; $j += $SizeJump1) { $Capacities += $j }
			}
			### $LastStep1 <= $LastSize < $LastStep2 ###
			elseIf ($LastSize -ge $LastStep1 -and $LastSize -lt $LastStep2)
			{
				$LastSizeTruncated = [Math]::Truncate($LastSize/$SizeJump2) * $SizeJump2
				
				for ($j = ($CapacityGB + $SizeJump1); $j -le $LastStep1; $j += $SizeJump1) { $Capacities += $j }
				for ($j = ($LastStep1 + $SizeJump2); $j -le $LastSizeTruncated; $j += $SizeJump2) { $Capacities += $j }
				if ($LastSize -gt $LastSizeTruncated) { $Capacities += $LastSize }
			}
			### $LastStep1 < $LastStep2 < $LastSize ###
			else
			{
				$LastSizeTruncated = [Math]::Truncate($LastSize/$SizeJump3) * $SizeJump3
				
				for ($j = ($CapacityGB + $SizeJump1); $j -le $LastStep1; $j += $SizeJump1) { $Capacities += $j }
				for ($j = ($LastStep1 + $SizeJump2); $j -le $LastStep2; $j += $SizeJump2) { $Capacities += $j }
				for ($j = ($LastStep2 + $SizeJump3); $j -le $LastSizeTruncated; $j += $SizeJump3) { $Capacities += $j }
				if ($LastSize -gt $LastSizeTruncated) { $Capacities += $LastSize }
			}
			
			### STEP 2 ###
			$SelectedCapacityGB = Write-Menu -Menu $Capacities -Header "Step [$i..$Steps]" -Prompt "Select desired Hard Disk capacity [GB]" -Shift 1
			$i++
			
			### Increase VM HardDisk ###
			if ($PSCmdlet.ShouldProcess("VM [$($VM.Name)]", "Increase VM Hard Disk [$SelectedHdd] from $OriginalCapacityGB to $SelectedCapacityGB GiB"))
			{
				Try
				{
					$null = . { Set-HardDisk -HardDisk $SelectedHdd -CapacityGB $SelectedCapacityGB -Confirm:$false -Verbose:$false }
				}
				Catch
				{
					Throw "Failed to increase the [$($SelectedHdd.Name)] Hard Disk!"
				}
			}
		}
		else { $Steps-- }
		
		### Expand VMGuest Partition ###
		$VMPartition = Get-VMGuestPartition -VM $VM | sort Volume
		$VMPartition | Format-Table -AutoSize
		
		### STEP 3 ###
		$SelectedPartition = Write-Menu -Menu $VMPartition -Header "Step [$i..$Steps]" -Prompt "Select a partition to extend" -Shift 1 -PropertyToShow Volume
		$Volume = $SelectedPartition.Volume.Replace(':\', '')
		$VMScript = "echo rescan > C:\DiskPart.txt && echo sel vol $Volume >> C:\DiskPart.txt && echo extend >> C:\DiskPart.txt && echo exit >> C:\DiskPart.txt && diskpart.exe /s C:\DiskPart.txt && del C:\DiskPart.txt /Q"
		
		if ($PSCmdlet.ShouldProcess("VM [$($VM.Name)]", "Extend VM Guest Partition [$($SelectedPartition.Volume)] from $($SelectedPartition.CapacityGB) GiB to a maximum available"))
		{
			$VMGuestCred = if ($PSCmdlet.ParameterSetName -eq 'CREDFILE')
			{
				Convert-VI2PSCredential -VICredentialStoreItem $GuestCred
			}
			else
			{
				New-Object System.Management.Automation.PSCredential($GuestUser, (ConvertTo-SecureString $GuestPassword -AsPlainText -Force))
			}
			
			$SelectedPartitionCapacityBefore = ($VMPartition | ? { $_.Volume -eq $SelectedPartition.Volume }).CapacityGB
			
			Try
			{
				$null = . {
					Invoke-VMScript -VM $VM -ScriptText $VMScript -ScriptType Bat `
									-HostCredential (Convert-VI2PSCredential -VICredentialStoreItem $HostCred) `
									-GuestCredential $VMGuestCred -RunAsync -Verbose:$false
				}
				Start-SleepProgress 40
			}
			Catch
			{
				"{0}" -f $Error.Exception.Message
			}
			Finally
			{
				$VMPartition = Get-VM $VM.Name -Verbose:$false | Get-VMGuestPartition | sort Volume
				$VMPartition | Format-Table -AutoSize
				
				$SelectedPartitionCapacityAfter = ($VMPartition | ? { $_.Volume -eq $SelectedPartition.Volume }).CapacityGB
				if ($SelectedPartitionCapacityAfter -gt $SelectedPartitionCapacityBefore)
				{
					Write-Verbose "The Partition [$($SelectedPartition.Volume)] successfully extended"
					$true
				}
				else
				{
					Write-Verbose "The Partition [$($SelectedPartition.Volume)] failed to extend"
					$false
				}
			}
		}
	}
	End { }
	
} #EndFunction Expand-VMGuestPartition

Function Get-ViSession
{
	
<#
.SYNOPSIS
	Get VCenter sessions.
.DESCRIPTION
	This function retrieves all VCenter sessions.
.EXAMPLE
	PS C:\> Get-ViSession
.EXAMPLE
	PS C:\> Get-ViSession -Idle 10000
	Get sessions idled more than one week.
.EXAMPLE
	PS C:\> Get-ViSession -User admin |fl
.EXAMPLE
	PS C:\> Get-ViSession "^$DomainName\\"
	List AD users only.
.EXAMPLE
	PS C:\> Get-ViSession -ExcludeServiceAccount:$true
.NOTES
	Idea        :: Alan Renouf @alanrenouf
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5.2
	Platform    :: Tested on vSphere 5.5/6.5 | VCenter 5.5U2/VCSA 6.5U1
	Requirement :: PowerShell 5.0
	Version 1.0 :: 21-Nov-2017 :: [Release] :: Publicly available
	Version 1.1 :: 22-Nov-2017 :: [Bugfix] :: Fixed error while connected directly to vSphere host or disconnected sessions saved in the $global:DefaultVIServers variable
.LINK
	https://ps1code.com/2017/11/21/vcenter-sessions-powercli
#>
	
	[CmdletBinding(DefaultParameterSetName = 'USER')]
	[OutputType([ViSession])]
	Param (
		[Parameter(Mandatory = $false, Position = 0, ParameterSetName = 'USER')]
		[ValidateNotNullorEmpty()]
		[string]$UserName
		 ,
		[Parameter(Mandatory, ParameterSetName = 'SERVICE')]
		[Alias("exs")]
		[boolean]$ExcludeServiceAccount
		 ,
		[Parameter(Mandatory, ParameterSetName = 'IDLE')]
		[double]$IdleTime
	)
	
	foreach ($VC in ($global:DefaultVIServers | ? { $_.IsConnected -and $_.ProductLine -eq 'vpx' }))
	{
		$SessionMgr = Get-View -Id SessionManager -Server $VC.Name -Verbose:$false
		$ViSessions = @()
		
		$SessionMgr.SessionList | % {
			
			### Try to resolve the Client IP ###
			if ('127.0.0.1', '::1' -notcontains $_.IpAddress)
			{
				$Resolve = nslookup $_.IpAddress 2>&1
				$Client = ([regex]::Match(([string]::Join(';', $Resolve)), '(?i)Name\:\s+(?<Hostname>.+?);')).Groups[1].Value
			}
			
			### The client type ###
			$ClientType = switch -regex ($_.UserAgent)
			{
				'(vim-java)' { 'Internal'; Break }
				'VI\sClient' { 'Legacy'; Break }
				'(Mozilla|web-client)' { 'Web Client'; Break }
				'PowerCLI' { 'PowerCLi' }
				Default { 'Unknown' }
			}
			
			$Session = [pscustomobject] @{
				VC = $VC.Name
				Key = $_.Key
				UserName = $_.UserName
				FullName = $_.FullName
				Client = if ($Client) { $Client } else { $_.IpAddress }
				ClientType = $ClientType
				LoginTime = ($_.LoginTime).ToLocalTime()
				LastActiveTime = ($_.LastActiveTime).ToLocalTime()
			}
			
			### Add session type ###
			if ($_.Key -eq $SessionMgr.CurrentSession.Key) { $Session | Add-Member -MemberType NoteProperty -Name Session -Value "_THIS_" }
			else { $Session | Add-Member -MemberType NoteProperty -Name Session -Value "Foreign" }
			
			### Add idle time ###
			$Session | Add-Member -MemberType NoteProperty -Name IdleMinutes -Value ([Math]::Round(((Get-Date) - ($_.LastActiveTime).ToLocalTime()).TotalMinutes))

			
			### Filter output out ###
			$ViSessions += if ($PSCmdlet.ParameterSetName -eq 'USER')
			{
				if ($Session.UserName -imatch $UserName) { $Session }
			}
			elseif ($PSCmdlet.ParameterSetName -eq 'SERVICE')
			{
				if ($ExcludeServiceAccount) { if ($_.UserName -notmatch '\\vpxd-extension') { $Session } }
				else { $Session }
			}
			else
			{
				if ($Session.IdleMinutes -gt $IdleTime) { $Session }
			}
		}
		[ViSession[]]$ViSessions | sort Session, IdleMinutes
	}
	
} #EndFunction Get-ViSession

Function Disconnect-ViSession
{
	
<#
.SYNOPSIS
	Disconnect opened VCenter sessions.
.DESCRIPTION
	This function terminates VCenter sessions.
.PARAMETER Session
	Specifies session object(s), returned by Get-VISession function.
.EXAMPLE
	PS C:\> Get-ViSession -Idle 10000 |Disconnect-ViSession -vb
	Close sessions that were being idle for more than one week.
.EXAMPLE
	PS C:\> Get-ViSession -UserName $env:USERNAME |Disconnect-ViSession
	Close all your user account sessions.
.EXAMPLE
	PS C:\> Get-ViSession |Disconnect-ViSession -Confirm:$false -Verbose
	Close all sessions with no confirmation!
.NOTES
	Idea        :: Alan Renouf @alanrenouf
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5.2
	Platform    :: Tested on vSphere 5.5/6.5 | VCenter 5.5U2/VCSA 6.5U1
	Requirement :: PowerShell 5.0
	Version 1.0 :: 21-Nov-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2017/11/21/vcenter-sessions-powercli
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[ViSession]$Session
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$SessionMgr = Get-View -Id SessionManager -Verbose:$false
	}
	Process
	{
		if ($Session.Status -ne '_THIS_' -and $Session.UserName -notmatch 'vpxd-extension')
		{
			if ($PSCmdlet.ShouldProcess("VC [$($Session.VC)]", "Terminate session for [$($Session.UserName)] which was not been active since [$($Session.LastActiveTime)]"))
			{
				Try { $SessionMgr.TerminateSession($Session.Key) }
				Catch { }
			}
		}
	}
	
} #EndFunction Disconnect-ViSession

Function New-SmartSnapshot
{
	
<#
.SYNOPSIS
	Create a new snapshot with progress bar.
.DESCRIPTION
	This function creates a new VMware VM snapshot or
	retrieves existing snapshots.
.PARAMETER Requestor
	Specifies snapshot requestor/owner, will be included in the snapshot name.
.PARAMETER VM
	Specifies VM object(s), returnd by Get-VM cmdlet.
.PARAMETER Description
	Specifies snapshot description to add to the default description.
.PARAMETER Force
	If specified, allows multiple snapshots for a single VM.
.EXAMPLE
	PS C:\> Get-VM vm1 |New-SmartSnapshot
.EXAMPLE
	PS C:\> Get-VM vm1, vm2 |New-SmartSnapshot -EjectCDDrive:$false
.EXAMPLE
	PS C:\> Get-VM vm1 |New-SmartSnapshot -Requestor user1
	Create a new snapshot with default description.
.EXAMPLE
	PS C:\> Get-VM 'vm2[45]' |New-SmartSnapshot user1 'Install Patches' -Force -Verbose
	Snap two VM, add optional description allowing multiple snapshots.
.EXAMPLE
	PS C:\> Get-VM |New-SmartSnapshot -ReportOnly
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5.2
	Platform    :: Tested on vSphere 5.5/6.5 | VCenter 5.5U2/VCSA 6.5U1
	Requirement :: PowerShell 3.0
	Dependency  :: Get-ViSession function (included in the module)
	Version 1.0 :: 22-Nov-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/category/vmware-powercli/vi-module/
#>
	
	[CmdletBinding(DefaultParameterSetName = 'NEW')]
	[Alias("New-ViMSmartSnapshot", "snap")]
	[OutputType([VMware.VimAutomation.Types.Snapshot])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$VM
		 ,
		[Parameter(Mandatory = $false, Position = 0, ParameterSetName = 'NEW')]
		[ValidateNotNullorEmpty()]
		[Alias("Owner")]
		[string]$Requestor = ($env:USERNAME)
		 ,
		[Parameter(Mandatory = $false, Position = 1, ParameterSetName = 'NEW')]
		[string]$Description
		 ,
		[Parameter(Mandatory = $false, ParameterSetName = 'NEW')]
		[switch]$Force
		 ,
		[Parameter(Mandatory = $false, ParameterSetName = 'NEW')]
		[boolean]$EjectCDDrive = $true
		 ,
		[Parameter(Mandatory, ParameterSetName = 'REP')]
		[switch]$ReportOnly
	)
	
	Begin
	{
		$ErrorActionPreference = 'SilentlyContinue'
		$SnapName = $Requestor + "__" + ([datetime]::Now).ToString('dd-MM-yyyy')
	}
	Process
	{
		$existSnap = Get-Snapshot -VM $VM -vb:$false
		
		if ($PSCmdlet.ParameterSetName -eq 'NEW')
		{
			
			if ($existSnap -and !$Force)
			{
				Write-Verbose "[$($VM.Name)]: Use [-Force] parameter to proceed VM with existing snapshots."
				$existSnap |
				select VM,
					   @{ N = 'Snapshot'; E = { $_.Name } },
					   Description,
					   @{ N = 'Type'; E = { 'Existing' } },
					   @{ N = 'Created'; E = { ($_.Created).ToString('dd"/"MM"/"yyyy HH:mm') } },
					   @{ N = 'SizeGiB'; E = { [Math]::Round($_.SizeMB/1024, 1) } },
					   @{ N = 'DaysOld'; E = { ([datetime]::Now - $_.Created).Days } } | sort Created
			}
			else
			{
				Try
				{
					if ($EjectCDDrive) { Get-CDDrive -VM $VM -vb:$false | ? { $_.IsoPath } | Set-CDDrive -NoMedia:$true -Confirm:$false -ea SilentlyContinue -vb:$false | Out-Null }
					
					$ParentVC = [regex]::Match($VM.Uid, '/VIServer=.+@(.+?):\d+').Groups[1].Value
					$SnapMaker = (Get-ViSession | ? { $_.VC -eq $ParentVC -and $_.Session -eq '_THIS_' }).UserName
					$SnapDescr = if ($Description) { "$SnapMaker - $Description" }
					else { $SnapMaker }
					
					### Make desicion regarding VM memory ###
					$Disks = ($VM | Get-HardDisk).Persistence
					$Memory = if ($Disks -contains 'IndependentPersistent' -or $Disks -contains 'IndependentNotPersistent') { $false }
					else { $true }
					
					$TaskMoRef = New-Snapshot -VM $VM -Name $SnapName -Description $SnapDescr -Memory:$Memory -Quiesce:$true -Confirm:$false -RunAsync -wa SilentlyContinue -vb:$false -Server $ParentVC
					$Task = Get-View $TaskMoRef -vb:$false
					
					for ($i = 1; $i -lt [int32]::MaxValue; $i++)
					{
						if ("running", "queued" -contains $Task.Info.State)
						{
							$Task.UpdateViewData("Info")
							if ($Task.Info.Progress -ne $null)
							{
								Write-Progress -Activity "Creating a snapshot ... $($Task.Info.Progress)%" -Status "VM [$($VM.Name)]" `
											   -CurrentOperation "Snapshot [$SnapName] - Description [$SnapDescr]" `
											   -PercentComplete $Task.Info.Progress -ea SilentlyContinue
								Start-Sleep -Seconds 3
							}
						}
						else
						{
							Write-Progress -Activity "Completed" -Completed
							Break
						}
					}
					
					if ($Task.Info.State -eq "error")
					{
						$Task.UpdateViewData("Info.Error")
						$Task.Info.Error.Fault.FaultMessage | % { $_.Message }
					}
					
					Get-Snapshot -VM $VM -vb:$false |
					select VM,
						   @{ N = 'Snapshot'; E = { $_.Name } },
						   Description,
						   @{ N = 'Type'; E = { '_THIS_' } },
						   @{ N = 'Created'; E = { ($_.Created).ToString('dd"/"MM"/"yyyy HH:mm') } },
						   @{ N = 'SizeGiB'; E = { [Math]::Round($_.SizeMB/1024, 1) } },
						   @{ N = 'DaysOld'; E = { ([datetime]::Now - $_.Created).Days } } | sort Created | select -Last 1
				}
				Catch { }
			}
		}
		else
		{
			$existSnap |
			select VM,
				   @{ N = 'Snapshot'; E = { $_.Name } },
				   Description,
				   @{ N = 'Type'; E = { 'Existing' } },
				   @{ N = 'Created'; E = { ($_.Created).ToString('dd"/"MM"/"yyyy HH:mm') } },
				   @{ N = 'SizeGiB'; E = { [Math]::Round($_.SizeMB/1024, 1) } },
				   @{ N = 'DaysOld'; E = { ([datetime]::Now - $_.Created).Days } } | sort Created
		}
	}
	End { }
	
} #EndFunction New-SmartSnapshot

Function Get-VMHostCDP
{
	
<#
.SYNOPSIS
	Get CDP info for ESXi hosts.
.DESCRIPTION
	This function retrieves CDP (Cisco Discovery Protocol) info for ESXi host(s).
.PARAMETER VMHost
	Specifies ESXi host object(s), returnd by Get-VMHost cmdlet.
.PARAMETER CdpOnly
	If specified, vmnics connected to non-CDP capable ports are excluded from the output.	
.EXAMPLE
	PS> Get-VMHost | Get-VMHostCDP
	Return default properties only.
.EXAMPLE
	PS> Get-VMHost esx1.* | Get-VMHostCDP | select * 
	Show all returned properties.
.EXAMPLE
	PS> Get-Cluster PROD | Get-VMHost | Get-VMHostCDP -CdpOnly | Export-Csv -notype .\Nexus.csv
	Export all CDP capable ports from particular Cluster.
.EXAMPLE
	PS> Get-VMHost | Get-VMHostCDP -CdpOnly | % { $_.ToString() }
	Show brief port-to-port view by static ToString() method.
.EXAMPLE
	PS> Get-Cluster PROD | Get-VMHost | Get-VMHostCDP -CdpOnly | % { $_.GetVlan() } | ? { $_.Vlan -eq 25 } | sort Switch, { [int]([regex]::Match($_.Port, '\d+$').Value) } | ft -au
	Show VLAN view by static GetVlan() method.
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5.2
	Platform    :: Tested on vSphere 5.5/6.5 | VCenter 5.5U2/VCSA 6.5U1 | Cisco Nexus 5000 Series
	Version 1.0 :: 25-Mar-2018 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2018/03/25/cdp-powercli
#>
	
	[CmdletBinding()]
	[Alias("Get-ViMVMHostCDP", "Get-ViMCDP")]
	[OutputType([ViCDP])]
	Param
	(
		[Parameter(Mandatory, ValueFromPipeline)]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$VMHost
		 ,
		[Parameter(Mandatory = $false)]
		[switch]$CdpOnly
	)
	
	Begin { $return = @() }
	Process
	{
		$ConfigManagerView = Get-View $VMHost.ExtensionData.ConfigManager.NetworkSystem
		$PNICs = $ConfigManagerView.NetworkInfo.Pnic
		
		foreach ($PNIC in $PNICs)
		{
			$PhysicalNicHintInfo = $ConfigManagerView.QueryNetworkHint($PNIC.Device)
			
			$Vendor = switch -regex ($PNIC.Driver)
			{
				'^(elx|be)' { 'Emulex'; Break }
				'^(igb|ixgb|e10)' { 'Intel'; Break }
				'^(bnx|tg|ntg)' { 'Broadcom'; Break }
				'^nmlx' { 'HPE'; Break }
				'^cdc' { 'IBM/LENOVO' }
				Default { 'Unknown' }
			}
			
			$portInfo = [ViCDP] @{
				VMHost = if ($VMHost.Name -match '\w') { [regex]::Match($VMHost.Name, '^(.+?)(\.|$)').Groups[1].Value } else { $VMHost.Name };
				NIC = $PNIC.Device;
				MAC = $PNIC.Mac.ToUpper();
				Vendor = $Vendor;
				Driver = $PNIC.Driver;
				CDP = if ($PhysicalNicHintInfo.ConnectedSwitchPort) { $true } else { $false };
				LinkMbps = if ($PNIC.LinkSpeed.SpeedMb) { $PNIC.LinkSpeed.SpeedMb } else { 0 };
				Switch = [string]$PhysicalNicHintInfo.ConnectedSwitchPort.DevId;
				Hardware = [string]$PhysicalNicHintInfo.ConnectedSwitchPort.HardwarePlatform;
				Software = [string]$PhysicalNicHintInfo.ConnectedSwitchPort.SoftwareVersion;
				MgmtIP = [ipaddress]$PhysicalNicHintInfo.ConnectedSwitchPort.MgmtAddr;
				MgmtVlan = [string]$PhysicalNicHintInfo.ConnectedSwitchPort.Vlan;
				PortId = [string]$PhysicalNicHintInfo.ConnectedSwitchPort.PortId;
				Vlan = if ($PhysicalNicHintInfo.Subnet.VlanId) { ($PhysicalNicHintInfo.Subnet.VlanId | sort) -join ', ' -as [string] } else { [string]::Empty };
			}
			if ($CdpOnly) { if ($portInfo.CDP) { $return += $portInfo } }
			else { $return += $portInfo }
		}
	}
	End { $return | sort VMHost, { [int]([regex]::Match($_.NIC, '\d+').Value) } }
	
} #EndFunction Get-VMHostCDP
