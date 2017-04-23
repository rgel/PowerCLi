Function Get-RDM {

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
	Author: Roman Gelman.
	Version 1.0 :: 16-Oct-2015 :: Release
	Version 1.1 :: 03-Dec-2015 :: Bugfix :: Error message appear while VML mismatch,
	when the VML identifier does not match for an RDM on two or more ESXi hosts.
	VMware [KB2097287].
	Version 1.2 :: 03-Aug-2016 :: Improvement :: GetType() method replaced by -is for type determine.
.LINK
	http://www.ps1code.com/single-post/2015/10/16/How-to-get-RDM-Raw-Device-Mappings-disks-using-PowerCLi
#>

[CmdletBinding()]
[Alias("Get-ViMRDM")]

Param (

	[Parameter(Mandatory=$false,Position=1,ValueFromPipeline=$true,HelpMessage="VM's collection, returned by Get-VM cmdlet")]
		[ValidateNotNullorEmpty()]
		[Alias("VM")]
	[VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$VMs = (Get-VM)

)

Begin {

	$Object    = @()
	$regxVMDK  = '^\[(?<Datastore>.+)\]\s(?<Filename>.+)$'
	$regxLUNID = ':L(?<LUNID>\d+)$'
}

Process {
	
	Foreach ($vm in ($VMs |Get-View)) {
		Foreach ($dev in $vm.Config.Hardware.Device) {
		    If ($dev -is [VMware.Vim.VirtualDisk]) {
				If ("physicalMode","virtualMode" -contains $dev.Backing.CompatibilityMode) {
		         	
					Write-Progress -Activity "Gathering RDM ..." -CurrentOperation "Hard disk - [$($dev.DeviceInfo.Label)]" -Status "VM - $($vm.Name)"
					
					$esx        = Get-View $vm.Runtime.Host
					$esxScsiLun = $esx.Config.StorageDevice.ScsiLun |? {$_.Uuid -eq $dev.Backing.LunUuid}
					
					### Expand 'LUNID' from device runtime name (vmhba2:C0:T0:L12) ###
					$lunCN = $esxScsiLun.CanonicalName
					$Matches = $null
					If ($lunCN) {
						$null  = (Get-ScsiLun -VmHost $esx.Name -CanonicalName $lunCN -ErrorAction SilentlyContinue).RuntimeName -match $regxLUNID
						$lunID = $Matches.LUNID
					} Else {$lunID = ''}
					
					### Expand 'Datastore' and 'VMDK' from file path ###
					$null = $dev.Backing.FileName -match $regxVMDK
					
					$Properties = [ordered]@{
						VM            = $vm.Name
						VMHost        = $esx.Name
						Datastore     = $Matches.Datastore
						VMDK          = $Matches.Filename
						HDLabel       = $dev.DeviceInfo.Label
						HDSizeGB      = [math]::Round(($dev.CapacityInKB / 1MB), 3)
						HDMode        = $dev.Backing.CompatibilityMode
						DeviceName    = $dev.Backing.DeviceName
						Vendor        = $esxScsiLun.Vendor
						CanonicalName = $lunCN
						LUNID         = $lunID
					}
					$Object = New-Object PSObject -Property $Properties
					$Object
				}
			}
		}
	}
}

End {
	Write-Progress -Completed $true -Status "Please wait"
}

} #EndFunction Get-RDM

Function Convert-VmdkThin2EZThick {

<#
.SYNOPSIS
	Inflate Thin Provision virtual disks.
.DESCRIPTION
	The Convert-VmdkThin2EZThick function converts Thin Provision VM disk(s) to the type 'Thick Provision Eager Zeroed'.
	Thick disks or disks with snapshots are skipped by the function.
.PARAMETER VM
	Object(s), returned by `Get-VM` cmdlet.
.EXAMPLE
	PowerCLI C:\> Get-VM VM1 |Convert-VmdkThin2EZThick
.EXAMPLE
	PowerCLI C:\> Get-VM VM1,VM2 |Convert-VmdkThin2EZThick -Confirm:$false |sort VM,Datastore,VMDK |ft -au
.EXAMPLE
	PowerCLI C:\> Get-VM 'vm[1-5]' |thin2thick -Verbose
.NOTES
	Author      :: Roman Gelman
	Shell       :: Tested on PowerShell 5.0|PowerCLi 6.5
	Platform    :: Tested on vSphere 5.5/6.0|VCenter 5.5U2/VCSA 6.0U1
	Requirement :: PowerShell 3.0+, VM must be PoweredOff
	Version 1.0 :: 05-Nov-2015 :: [Release]
	Version 1.1 :: 03-Aug-2016 :: [Change] :: Parameter `-VMs` renamed to `-VM`
	Version 1.2 :: 18-Jan-2017 :: [Change] :: Cofirmation asked on per-disk basis instead of per-VM, added `Write-Warning` and `Write-Verbose` messages, minor code changes
.LINK
	http://www.ps1code.com/single-post/2015/11/05/How-to-convert-Thin-Provision-VMDK-disks-to-Eager-Zeroed-Thick-using-PowerCLi
#>

[CmdletBinding(ConfirmImpact='High',SupportsShouldProcess=$true)]
[Alias("Convert-ViMVmdkThin2EZThick","thin2thick")]
[OutputType([PSCustomObject])]

Param (
	[Parameter(Mandatory,Position=0,ValueFromPipeline)]
		[Alias("VMs")]
	[VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$VM
)

Begin {
	$Object   = @()
	$regxVMDK = '^\[(?<Datastore>.+)\]\s(?<Filename>.+)$'
} #EndBegin

Process {
	
	Foreach ($vmv in ($VM |Get-View -Verbose:$false)) {
	
		### Validate VM prerequisites ###
		If ($vmv.Runtime.PowerState -eq 'poweredOff') {
		
			### Get ESXi object where $vmv is registered ###
			$esx = Get-View $vmv.Runtime.Host -Verbose:$false
			
			### Get Datacenter object where $vmv is registered ###
			$parentObj = Get-View $vmv.Parent -Verbose:$false
		    While ($parentObj -isnot [VMware.Vim.Datacenter]) {$parentObj = Get-View $parentObj.Parent -Verbose:$false}
		    $datacenter       = New-Object VMware.Vim.ManagedObjectReference
			$datacenter.Type  = 'Datacenter'
			$datacenter.Value = $parentObj.MoRef.Value
		   
			Foreach ($dev in $vmv.Config.Hardware.Device) {
			    If ($dev -is [VMware.Vim.VirtualDisk]) {
				
					$sizeGB = [Math]::Round(($dev.CapacityInKB / 1MB), 1)
					If ($dev.Backing.ThinProvisioned -and !($dev.Backing.Parent) -and $PSCmdlet.ShouldProcess("VM [$($vmv.Name)]","Convert $sizeGB GiB Thin Provision disk [$($dev.DeviceInfo.Label)] to [Thick Provision Eager Zeroed]")) {
			
						### Invoke 'Inflate virtual disk' task ###
						$ViDM      = Get-View -Id 'VirtualDiskManager-virtualDiskManager' -Verbose:$false
						$taskMoRef = $ViDM.InflateVirtualDisk_Task($dev.Backing.FileName, $datacenter)
						$task      = Get-View $taskMoRef -Verbose:$false
						
						### Show task progress ###
						For ($i=1; $i -lt [int32]::MaxValue; $i++) {
							If ("running","queued" -contains $task.Info.State) {
								$task.UpdateViewData("Info")
								If ($task.Info.Progress -ne $null) {
									Write-Progress -Activity "Inflate virtual disk task is in progress ..." -Status "VM [$($vmv.Name)]" `
									-CurrentOperation "[$($dev.DeviceInfo.Label)] :: $($dev.Backing.FileName) [$sizeGB GiB]" `
									-PercentComplete $task.Info.Progress -ErrorAction SilentlyContinue
									Start-Sleep -Seconds 3
								}
							}
 							Else {Break}
						}
						
						### Get task completion results ###
						$tResult       = $task.Info.State
						$tStart        = $task.Info.StartTime
						$tEnd          = $task.Info.CompleteTime
						$tCompleteTime = [Math]::Round((New-TimeSpan -Start $tStart -End $tEnd).TotalMinutes, 1)
						
						### Expand 'Datastore' and 'VMDK' from file path ###
						$null = $dev.Backing.FileName -match $regxVMDK
						
						$Properties = [ordered]@{
							VM           = $vmv.Name
							VMHost       = $esx.Name
							Datastore    = $Matches.Datastore
							VMDK         = $Matches.Filename
							HDLabel      = $dev.DeviceInfo.Label
							HDSizeGB     = $sizeGB
							Result       = (Get-Culture).TextInfo.ToTitleCase($tResult)
							StartTime    = $tStart
							CompleteTime = $tEnd
							TimeMin      = $tCompleteTime
						}
						$Object = New-Object PSObject -Property $Properties
						$Object
					} Else {Write-Verbose "VM [$($vmv.Name)] :: [$($dev.DeviceInfo.Label)] :: $($dev.Backing.FileName) skipped"}
				}
			}
			$vmv.Reload()
		} Else {Write-Warning "VM [$($vmv.Name)] must be PoweredOff, but currently it is [$($vmv.Runtime.PowerState)]!"}
	}
} #EndProcess

End {
	Write-Progress -Activity "Completed" -Completed
	#Write-Progress -Completed $true -Status "Please wait"
} #End

} #EndFunction Convert-VmdkThin2EZThick

Function Find-VcVm {

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
	Author      :: Roman Gelman.
	Limitation  :: [1] The function uses common credentials for all ESXi hosts.
	               [2] The hosts' Lockdown mode should be disabled.
	Version 1.0 :: 03-Sep-2015 :: Release.
	Version 1.1 :: 03-Aug-2016 :: Improvement :: Returned object properties changed.
	Version 1.2 :: 14-Nov-2016 :: Improvement :: Disappear unnecessary error messages while disconnecting VC.
.OUTPUTS
	[System.Management.Automation.PSCustomObject] PSObject collection.
.LINK
	http://ps1code.com
#>

[Alias("Find-ViMVcVm")]

Param (

	[Parameter(Mandatory=$true,Position=1,HelpMessage="vCenter's VM Name")]
		[Alias("vCenter","VcVm")]
	[string]$VC
	,
	[Parameter(Mandatory=$true,Position=2,HelpMessage="ESXi Hosts' common suffix")]
		[Alias("VMHostSuffix","ESXiSuffix")]
	[string]$HostSuffix
	,
	[Parameter(Mandatory=$false,Position=3,HelpMessage="ESXi Hosts' postfix number start")]
		[ValidateRange(1,98)]
		[Alias("PostfixFirst","Start")]
	[int]$PostfixStart = 1
	,
	[Parameter(Mandatory=$false,Position=4,HelpMessage="ESXi Hosts' postfix number end")]
		[ValidateRange(2,99)]
		[Alias("PostfixLast","End")]
	[int]$PostfixEnd = 9
	,
	[Parameter(Mandatory=$false,Position=5,HelpMessage="Add ESXi Hosts' postfix leading zero")]
	[switch]$AddZero = $false
)

Begin {

	Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Scope Session -Confirm:$false |Out-Null
	If ($PostfixEnd -le $PostfixStart) {Throw "PostfixEnd must be greater than PostfixStart"}
	Try {Disconnect-VIServer -Server $VC -Force -Confirm:$false -ErrorAction Stop}  Catch {}
}

Process {

	$cred = Get-Credential -UserName root -Message "Common VMHost Credentials"
	If ($cred) {
		$hosts = @()
		
		For ($i=$PostfixStart; $i -le $PostfixEnd; $i++) {
			If ($AddZero -and $i -match '^\d{1}$') {
				$hosts += $HostSuffix + '0' + $i
			} Else {
				$hosts += $HostSuffix + $i
			}
		}
		
		Connect-VIServer $hosts -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -Credential $cred |
		select @{N='VMHost';E={$_.Name}},IsConnected |ft -AutoSize
		
		If ($global:DefaultVIServers.Length -ne 0) {
			$TargetVM       = Get-VM -ErrorAction SilentlyContinue |? {$_.Name -eq $VC}
			$VCHostname     = $TargetVM.Guest.HostName
			$PowerState     = $TargetVM.PowerState
			$VMHostHostname = $TargetVM.VMHost.Name
			Try {Disconnect-VIServer -Server "$HostSuffix*" -Force -Confirm:$false -ErrorAction Stop}  Catch {}
		}
	}
}

End {

	If ($TargetVM)	{
		$Properties = [ordered]@{
			VC         = $VC
			Hostname   = $VCHostname
			PowerState = $PowerState
			VMHost     = $VMHostHostname
		}
		$Object = New-Object PSObject -Property $Properties
		$Object
	}
}

} #EndFunction Find-VcVm

Function Set-PowerCLiTitle {

<#
.SYNOPSIS
	Write connected VI servers info to PowerCLi window title bar.
.DESCRIPTION
	This function writes connected VI servers info to PowerCLi window/console title bar
	in the following format: [VIServerName :: ProductType (VCenter/VCSA/ESXi/SRM)-ProductVersion].
.EXAMPLE
	PowerCLI C:\> Connect-VIServer $VCName -WarningAction SilentlyContinue
	PowerCLI C:\> Set-PowerCLiTitle
.EXAMPLE
	PowerCLI C:\> Connect-SrmServer $SRMServerName
	PowerCLI C:\> title
.NOTES
	Author      :: Roman Gelman
	Version 1.0 :: 17-Nov-2015 :: [Release]
	Version 1.1 :: 22-Aug-2016 :: [Improvement]
	[1] Added support for SRM servers
	[2] Now the function differs berween VCSA and Windows VCenters
	[3] Minor visual changes
	Version 1.2 :: 11-Jan-2017 :: [Change] :: Now this is advanced function, minor code changes
.LINK
	http://www.ps1code.com/single-post/2015/11/17/ConnectVIServer-deep-dive-or-%C2%ABWhere-am-I-connected-%C2%BB
#>

[CmdletBinding()]
[Alias("Set-ViMPowerCLiTitle","title")]
Param()

Begin {
	$VIS = $global:DefaultVIServers |sort -Descending ProductLine,Name
	$SRM = $global:DefaultSrmServers |sort -Descending ProductLine,Name
} #EndBegin

Process {

	If ($VIS) {
		Foreach ($VIObj in $VIS) {
			If ($VIObj.IsConnected) {
				$VIProduct = Switch -exact ($VIObj.ProductLine) {
					vpx     	{If ($VIObj.ExtensionData.Content.About.OsType -match '^linux') {'VCSA'} Else {'VCenter'}; Break}
					embeddedEsx {'ESXi'; Break}
					Default     {$VIObj.ProductLine}
				}
				$Header += "[$($VIObj.Name) :: $VIProduct-$($VIObj.Version)] "
			}
		}
	}

	If ($SRM) {
		Foreach ($VIObj in $SRM) {
			If ($VIObj.IsConnected) {
				$VIProduct = Switch -exact ($VIObj.ProductLine) {
					srm     {'SRM'; Break}
					Default {$VIObj.ProductLine}
				}
				$Header += "[$($VIObj.Name) :: $VIProduct-$($VIObj.Version)] "
			}
		}
	}
} #EndProcess

End {
	If (!$VIS -and !$SRM) {$Header = ':: Not connected to any VI Servers ::'}
	$Host.UI.RawUI.WindowTitle = $Header
} #End

} #EndFunction Set-PowerCLiTitle

Filter Get-VMHostFirmwareVersion {

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
	Author: Roman Gelman.
	Version 1.0 :: 09-Jan-2016 :: Release.
	Version 1.1 :: 03-Aug-2016 :: Improvement :: GetType() method replaced by -is for type determine.
.LINK
	http://www.ps1code.com/single-post/2016/1/9/How-to-know-ESXi-servers%E2%80%99-BIOSFirmware-version-using-PowerCLi
#>

Try
	{
		If     ($_ -is [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]) {$BiosInfo = ($_ |Get-View).Hardware.BiosInfo}
		ElseIf ($_ -is [VMware.Vim.HostSystem])                                 {$BiosInfo = $_.Hardware.BiosInfo}
		ElseIf ($_ -is [string])                                                {$BiosInfo = (Get-View -ViewType HostSystem -Filter @{"Name" = $_}).Hardware.BiosInfo}
		Else   {Throw "Not supported data type as pipeline"}

		$fVersion = $BiosInfo.BiosVersion -replace ('^-\[|\]-$', $null)
		$fDate    = [Regex]::Match($BiosInfo.ReleaseDate, '(\d{1,2}/){2}\d+').Value
		If ($fVersion) {return "$fVersion [$fDate]"} Else {return $null}
	}
Catch
	{}
} #EndFilter Get-VMHostFirmwareVersion
New-Alias -Name Get-ViMVMHostFirmwareVersion -Value Get-VMHostFirmwareVersion -Force:$true

Filter Get-VMHostFirmwareVersion {

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
	Author: Roman Gelman.
	Version 1.0 :: 09-Jan-2016 :: Release.
	Version 1.1 :: 03-Aug-2016 :: Improvement :: GetType() method replaced by -is for type determine.
.LINK
	http://www.ps1code.com/single-post/2016/1/9/How-to-know-ESXi-servers%E2%80%99-BIOSFirmware-version-using-PowerCLi
#>

Try
	{
		If     ($_ -is [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]) {$BiosInfo = ($_ |Get-View).Hardware.BiosInfo}
		ElseIf ($_ -is [VMware.Vim.HostSystem])                                 {$BiosInfo = $_.Hardware.BiosInfo}
		ElseIf ($_ -is [string])                                                {$BiosInfo = (Get-View -ViewType HostSystem -Filter @{"Name" = $_}).Hardware.BiosInfo}
		Else   {Throw "Not supported data type as pipeline"}

		$fVersion = $BiosInfo.BiosVersion -replace ('^-\[|\]-$', $null)
		$fDate    = [Regex]::Match($BiosInfo.ReleaseDate, '(\d{1,2}/){2}\d+').Value
		If ($fVersion) {return "$fVersion [$fDate]"} Else {return $null}
	}
Catch
	{}
} #EndFilter Get-VMHostFirmwareVersion
New-Alias -Name Get-ViMVMHostFirmwareVersion -Value Get-VMHostFirmwareVersion -Force:$true

Filter Get-VMHostBirthday {

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
	Original idea: Magnus Andersson
	Author:        Roman Gelman
	Requirements:  vSphere 5.x or above
.LINK
	http://vcdx56.com/2016/01/05/find-esxi-installation-date/
#>

Try
	{
		$EsxCli = Get-EsxCli -VMHost $_ -ErrorAction Stop
		$Uuid   = $EsxCli.system.uuid.get()
		$bdHexa = [Regex]::Match($Uuid, '^(\w{8,})-').Groups[1].Value
		$bdDeci = [Convert]::ToInt64($bdHexa, 16)
		$bdDate = [TimeZone]::CurrentTimeZone.ToLocalTime(([DateTime]'1/1/1970').AddSeconds($bdDeci))
		If ($bdDate) {return $bdDate} Else {return $null}
	}
Catch
	{ }
} #EndFilter Get-VMHostBirthday
New-Alias -Name Get-ViMVMHostBirthday -Value Get-VMHostBirthday -Force:$true

Function Enable-VMHostSSH {

<#
.SYNOPSIS
	Enable SSH on all ESXi hosts in a cluster.
.DESCRIPTION
	This function enables SSH on all ESXi hosts in a cluster.
	It starts the SSH daemon and opens incoming TCP connections on port 22.
.EXAMPLE
	PS C:\> Get-Cluster PROD |Enable-VMHostSSH
.EXAMPLE
	PS C:\> Get-Cluster DEV,TEST |Enable-VMHostSSH |sort Cluster,VMHost |Format-Table -AutoSize
.INPUTS
	[VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl[]] Clusters collection, returtned by Get-Cluster cmdlet.
.OUTPUTS
	[System.Management.Automation.PSCustomObject] PSObject collection.
.NOTES
	Author      ::	Roman Gelman.
	Version 1.0 :: 07-Feb-2016 :: Release.
	Version 1.1 :: 02-Aug-2016 :: -Cluster parameter data type changed to the portable type.
.LINK
	http://www.ps1code.com/single-post/2016/02/07/How-to-enabledisable-SSH-on-all-ESXi-hosts-in-a-cluster-using-PowerCLi
#>

[Alias("Enable-ViMVMHostSSH")]

Param (

	[Parameter(Mandatory=$false,Position=0,ValueFromPipeline=$true)]
		[ValidateNotNullorEmpty()]
	[VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster[]]$Cluster = (Get-Cluster)
)

Process {

	Foreach ($container in $Cluster) {
		Foreach ($esx in Get-VMHost -Location $container) {
			
			If ('Connected','Maintenance' -contains $esx.ConnectionState -and $esx.PowerState -eq 'PoweredOn') {
			
				$sshSvc = Get-VMHostService -VMHost $esx |? {$_.Key -eq 'TSM-SSH'} |Start-VMHostService -Confirm:$false -ErrorAction Stop
				If ($sshSvc.Running) {$sshStatus = 'Running'} Else {$sshStatus = 'NotRunning'}
				$fwRule = Get-VMHostFirewallException -VMHost $esx -Name 'SSH Server' |Set-VMHostFirewallException -Enabled $true -ErrorAction Stop
				
				$Properties = [ordered]@{
					Cluster    = $container.Name
					VMHost     = $esx.Name
					State      = $esx.ConnectionState
					PowerState = $esx.PowerState
					SSHDaemon  = $sshStatus
					SSHEnabled = $fwRule.Enabled
				}
			}
			Else {
			
				$Properties = [ordered]@{
					Cluster    = $container.Name
					VMHost     = $esx.Name
					State      = $esx.ConnectionState
					PowerState = $esx.PowerState
					SSHDaemon  = 'Unknown'
					SSHEnabled = 'Unknown'
				}
			}
			$Object = New-Object PSObject -Property $Properties
			$Object
		}
	}

}

} #EndFunction Enable-VMHostSSH

Function Disable-VMHostSSH {

<#
.SYNOPSIS
	Disable SSH on all ESXi hosts in a cluster.
.DESCRIPTION
	This function disables SSH on all ESXi hosts in a cluster.
	It stops the SSH daemon and (optionally) blocks incoming TCP connections on port 22.
.PARAMETER BlockFirewall
	Try to disable "SSH Server" firewall exception rule.
	It might fail if this rule categorized as "Required Services" (VMware KB2037544).
.EXAMPLE
	PS C:\> Get-Cluster PROD |Disable-VMHostSSH -BlockFirewall
.EXAMPLE
	PS C:\> Get-Cluster DEV,TEST |Disable-VMHostSSH |sort Cluster,VMHost |Format-Table -AutoSize
.INPUTS
	[VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl[]] Clusters collection, returtned by Get-Cluster cmdlet.
.OUTPUTS
	[System.Management.Automation.PSCustomObject] PSObject collection.
.NOTES
	Author      ::	Roman Gelman.
	Version 1.0 :: 07-Feb-2016 :: Release.
	Version 1.1 :: 02-Aug-2016 :: -Cluster parameter data type changed to the portable type.
.LINK
	http://www.ps1code.com/single-post/2016/02/07/How-to-enabledisable-SSH-on-all-ESXi-hosts-in-a-cluster-using-PowerCLi
#>

[Alias("Disable-ViMVMHostSSH")]

Param (

	[Parameter(Mandatory=$false,Position=0,ValueFromPipeline=$true)]
		[ValidateNotNullorEmpty()]
	[VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster[]]$Cluster = (Get-Cluster)
	,
	[Parameter(Mandatory=$false,Position=1)]
	[Switch]$BlockFirewall
)

Process {

	Foreach ($container in $Cluster) {
		Foreach ($esx in Get-VMHost -Location $container) {
			
			If ('Connected','Maintenance' -contains $esx.ConnectionState -and $esx.PowerState -eq 'PoweredOn') {
			
				$sshSvc = Get-VMHostService -VMHost $esx |? {$_.Key -eq 'TSM-SSH'} |Stop-VMHostService -Confirm:$false -ErrorAction Stop
				If ($sshSvc.Running) {$sshStatus = 'Running'} Else {$sshStatus = 'NotRunning'}
				$fwRule = Get-VMHostFirewallException -VMHost $esx -Name 'SSH Server'
				If ($BlockFirewall) {
					Try   {$fwRule = Set-VMHostFirewallException -Exception $fwRule -Enabled:$false -Confirm:$false -ErrorAction Stop}
					Catch {}
				}
				
				$Properties = [ordered]@{
					Cluster    = $container.Name
					VMHost     = $esx.Name
					State      = $esx.ConnectionState
					PowerState = $esx.PowerState
					SSHDaemon  = $sshStatus
					SSHEnabled = $fwRule.Enabled
				}
			}
			Else {
			
				$Properties = [ordered]@{
					Cluster    = $container.Name
					VMHost     = $esx.Name
					State      = $esx.ConnectionState
					PowerState = $esx.PowerState
					SSHDaemon  = 'Unknown'
					SSHEnabled = 'Unknown'
				}
			}
			$Object = New-Object PSObject -Property $Properties
			$Object
		}
	}

}

} #EndFunction Disable-VMHostSSH

Function Set-VMHostNtpServer {

<#
.SYNOPSIS
	Set NTP server settings on a group of ESXi hosts.
.DESCRIPTION
	This cmdlet sets NTP server settings on a group of ESXi hosts
	and restarts the NTP daemon to apply these settings.
.PARAMETER VMHost
	ESXi hosts.
.PARAMETER NewNtp
	NTP servers (IP/Hostname).
.EXAMPLE
	PS C:\> Set-VMHostNtpServer -NewNtp 'ntp1','ntp2'
	Set two NTP servers to all hosts in inventory.
.EXAMPLE
	PS C:\> Get-VMHost 'esx1.*','esx2.*' |Set-VMHostNtpServer -NewNtp 'ntp1','ntp2'
.EXAMPLE
	PS C:\> Get-Cluster DEV,TEST |Get-VMHost |sort Parent,Name |Set-VMHostNtpServer -NewNtp 'ntp1','10.1.2.200' |ft -au
.EXAMPLE
	PS C:\> Get-VMHost -Location Datacenter1 |sort Name |Set-VMHostNtpServer -NewNtp 'ntp1','ntp2' |epcsv -notype -Path '.\Ntp_report.csv'
	Export the results to Excel.
.INPUTS
	[VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost[]] VMHost collection returned by Get-VMHost cmdlet.
.OUTPUTS
	[System.Management.Automation.PSCustomObject] PSObject collection.
.NOTES
	Author      ::	Roman Gelman.
	Version 1.0 ::	10-Mar-2016  :: Release.
.LINK
	http://www.ps1code.com/single-post/2016/03/10/How-to-configure-NTP-servers-setting-on-ESXi-hosts-using-PowerCLi
#>

[CmdletBinding()]
[Alias("Set-ViMVMHostNtpServer")]

Param (

	[Parameter(Mandatory=$false,Position=1,ValueFromPipeline=$true)]
		[ValidateNotNullorEmpty()]
	[VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost[]]$VMHost = (Get-VMHost)
	,
	[Parameter(Mandatory,Position=2)]
	[System.String[]]$NewNtp
)

Begin {
	$ErrorActionPreference = 'Stop'
}

Process {

	Foreach ($esx in $VMHost) {
	
		If ('Connected','Maintenance' -contains $esx.ConnectionState -and $esx.PowerState -eq 'PoweredOn') {

			### Get current Ntp ###
			$Ntps = Get-VMHostNtpServer -VMHost $esx
			
			### Remove previously configured Ntp ###
			$removed = $false
			Try
			{
				Remove-VMHostNtpServer -NtpServer $Ntps -VMHost $esx -Confirm:$false
				$removed = $true
			}
			Catch { }

			### Add new Ntp ###
			$added = $null
			Try
			{
				$added = Add-VMHostNtpServer -NtpServer $NewNtp -VMHost $esx -Confirm:$false
			}
			Catch { }
			
			### Restart NTP Daemon ###
			$restarted = $false
			Try
			{
				If ($added) {Get-VMHostService -VMHost $esx |? {$_.Key -eq 'ntpd'} |Restart-VMHostService -Confirm:$false |Out-Null}
				$restarted = $true
			}
			Catch {}
			
			### Return results ###
			$Properties = [ordered]@{
				VMHost            = $esx
				OldNtp            = $Ntps
				IsOldRemoved      = $removed
				NewNtp            = $added
				IsDaemonRestarted = $restarted
			}
			$Object = New-Object PSObject -Property $Properties
			$Object
		}
		Else {Write-Warning "VMHost '$($esx.Name)' is in unsupported state"}
	}

}

} #EndFunction Set-VMHostNtpServer

Function Get-Version {

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
	Author       ::	Roman Gelman.
	Version 1.0  ::	23-May-2016  :: Release.
	Version 1.1  ::	03-Aug-2016  :: Bugfix ::
	[1] VDSwitch data type changed from [VMware.Vim.VmwareDistributedVirtualSwitch] to [VMware.VimAutomation.Vds.Types.V1.VmwareVDSwitch].
	[2] Function Get-VersionVDSwitch edited to support data type change.
.LINK
	http://www.ps1code.com/single-post/2016/05/25/How-to-know-any-VMware-object%E2%80%99s-version-Use-GetVersion
#>

[CmdletBinding(DefaultParameterSetName='VIO')]
[Alias("Get-ViMVersion")]

Param (

	[Parameter(Mandatory,Position=1,ValueFromPipeline=$true,ParameterSetName='VIO')]
	$VIObject
	,
	[Parameter(Mandatory,Position=1,ParameterSetName='VC')]
	[switch]$VCenter
	,
	[Parameter(Mandatory,Position=1,ParameterSetName='LIC')]
	[switch]$LicenseKey
)

Begin {

	$ErrorActionPreference = 'SilentlyContinue'
	
	Function Get-VersionVMHostImpl {
	Param ([Parameter(Mandatory,Position=1)]$InputObject)
	$ErrorActionPreference = 'Stop'
	Try
		{
			If ('Connected','Maintenance' -contains $InputObject.ConnectionState -and $InputObject.PowerState -eq 'PoweredOn') {
				$ProductInfo = $InputObject.ExtensionData.Config.Product
				$ProductVersion = [version]($ProductInfo.Version + '.' + $ProductInfo.Build)
				
				$Properties = [ordered]@{
					ProductName = $InputObject.Name
					ProductType = $ProductInfo.Name
					FullVersion = $ProductInfo.FullName
					Version     = $ProductVersion
				}
			}
			Else {
				$Properties = [ordered]@{
					ProductName = $InputObject.Name
					ProductType = 'VMware ESXi'
					FullVersion = 'Unknown'
					Version     = [version]'0.0.0.0'
				}
			}
		}
	Catch
		{
			$Properties = [ordered]@{
				ProductName = $InputObject.Name
				ProductType = 'VMware ESXi'
				FullVersion = 'Unknown'
				Version     = [version]'0.0.0.0'
			}
		}
	Finally
		{
			$Object = New-Object PSObject -Property $Properties
			$Object
		}
		
	} #EndFunction Get-VersionVMHostImpl
	
	Function Get-VersionVMHostView {
	Param ([Parameter(Mandatory,Position=1)]$InputObject)
	$ErrorActionPreference = 'Stop'
	Try
		{
			$ProductRuntime = $InputObject.Runtime
			If ('connected','maintenance' -contains $ProductRuntime.ConnectionState -and $ProductRuntime.PowerState -eq 'poweredOn') {
				$ProductInfo = $InputObject.Config.Product
				$ProductVersion = [version]($ProductInfo.Version + '.' + $ProductInfo.Build)
				
				$Properties = [ordered]@{
					ProductName = $InputObject.Name
					ProductType = $ProductInfo.Name
					FullVersion = $ProductInfo.FullName
					Version     = $ProductVersion
				}
			}
			Else {
				$Properties = [ordered]@{
					ProductName = $InputObject.Name
					ProductType = 'VMware ESXi'
					FullVersion = 'Unknown'
					Version     = [version]'0.0.0.0'
				}
			}
		}
	Catch
		{
			$Properties = [ordered]@{
				ProductName = $InputObject.Name
				ProductType = 'VMware ESXi'
				FullVersion = 'Unknown'
				Version     = [version]'0.0.0.0'
			}
		}
	Finally
		{
			$Object = New-Object PSObject -Property $Properties
			$Object
		}
		
	} #EndFunction Get-VersionVMHostView
	
	Function Get-VersionVM {
	Param ([Parameter(Mandatory,Position=1)]$InputObject)
	$ErrorActionPreference = 'Stop'
	Try
		{
			$ProductInfo = $InputObject.Guest
			
			If ($InputObject.ExtensionData.Guest.ToolsStatus -ne 'toolsNotInstalled' -and $ProductInfo) {	
				$ProductVersion = [version]$ProductInfo.ToolsVersion
				
				$Properties = [ordered]@{
					ProductName = $InputObject.Name
					ProductType = $InputObject.ExtensionData.Config.GuestFullName  #$ProductInfo.OSFullName
					FullVersion = "VMware VM " + $InputObject.Version
					Version     = $ProductVersion
				}
			}
			Else {
			
				$Properties = [ordered]@{
					ProductName = $InputObject.Name
					ProductType = $InputObject.ExtensionData.Config.GuestFullName
					FullVersion = "VMware VM " + $InputObject.Version
					Version     = [version]'0.0.0'
				}
			}
		}
	Catch
		{
			$Properties = [ordered]@{
				ProductName = $InputObject.Name
				ProductType = 'Unknown'
				FullVersion = 'VMware VM'
				Version     = [version]'0.0.0'
			}
		}
	Finally
		{
			$Object = New-Object PSObject -Property $Properties
			$Object
		}
		
	} #EndFunction Get-VersionVM
	
	Function Get-VersionPowerCLi {
	$ErrorActionPreference = 'Stop'
		Try
			{
				$PCLi = Get-PowerCLIVersion
				$PCLiVer = [string]$PCLi.Major + '.' + [string]$PCLi.Minor + '.' + [string]$PCLi.Revision + '.' + [string]$PCLi.Build
				
				$Properties = [ordered]@{
					ProductName = $env:COMPUTERNAME
					ProductType = 'VMware vSphere PowerCLi'
					FullVersion = $PCLi.UserFriendlyVersion
					Version     = [version]$PCLiVer
				}
				$Object = New-Object PSObject -Property $Properties
				$Object
			}
		Catch {}	
	} #EndFunction Get-VersionPowerCLi
	
	Function Get-VersionVCenter {
	Param ([Parameter(Mandatory,Position=1)]$InputObject)
	$ErrorActionPreference = 'Stop'
	Try
		{
			If ($obj.IsConnected) {
				$ProductInfo = $InputObject.ExtensionData.Content.About
				$ProductVersion = [version]($ProductInfo.Version + '.' + $ProductInfo.Build)
				Switch -regex ($ProductInfo.OsType) {
					'^win'   {$ProductFullName = $ProductInfo.Name + ' Windows'   ;Break}
					'^linux' {$ProductFullName = $ProductInfo.Name + ' Appliance' ;Break}
					Default  {$ProductFullName = $ProductInfo.Name                ;Break}
				}
				
				$Properties = [ordered]@{
					ProductName = $InputObject.Name
					ProductType = $ProductFullName
					FullVersion = $ProductInfo.FullName
					Version     = $ProductVersion
				}
			}
			Else {
				$Properties = [ordered]@{
					ProductName = $InputObject.Name
					ProductType = 'VMware vCenter Server'
					FullVersion = 'Unknown'
					Version     = [version]'0.0.0.0'
				}
			}
		}
	Catch
		{
			$Properties = [ordered]@{
				ProductName = $InputObject.Name
				ProductType = 'VMware vCenter Server'
				FullVersion = 'Unknown'
				Version     = [version]'0.0.0.0'
			}
		}
	Finally
		{
			$Object = New-Object PSObject -Property $Properties
			$Object
		}
		
	} #EndFunction Get-VersionVCenter
	
	Function Get-VersionVDSwitch {
	Param ([Parameter(Mandatory,Position=1)]$InputObject)
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
				Version     = $ProductVersion
			}
		}
	Catch
		{
			$Properties = [ordered]@{
				ProductName = $InputObject.Name
				ProductType = $ProductTypeName
				FullVersion = 'Unknown'
				Version     = [version]'0.0.0.0'
			}
		}
	Finally
		{
			$Object = New-Object PSObject -Property $Properties
			$Object
		}
		
	} #EndFunction Get-VersionVDSwitch
	
	Function Get-VersionDatastore {
	Param ([Parameter(Mandatory,Position=1)]$InputObject)
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
				Version     = $ProductVersion
			}
		}
	Catch
		{
			$Properties = [ordered]@{
				ProductName = $InputObject.Name
				ProductType = $ProductTypeName
				FullVersion = 'Unknown'
				Version     = [version]'0.0'
			}
		}
	Finally
		{
			$Object = New-Object PSObject -Property $Properties
			$Object
		}
		
	} #EndFunction Get-VersionDatastore
	
	Function Get-VersionLicenseKey {
	Param ([Parameter(Mandatory,Position=1)]$InputObject)
	$ErrorActionPreference = 'Stop'
	$ProductTypeName = 'License Key'
	Try
		{
			$InputObjectProp = $InputObject |select -ExpandProperty Properties
			Foreach ($prop in $InputObjectProp) {
				If ($prop.Key -eq 'ProductName')        {$ProductType    = $prop.Value + ' ' + $ProductTypeName}
				ElseIf ($prop.Key -eq 'ProductVersion') {$ProductVersion = [version]$prop.Value}
			}
			
			Switch -regex ($InputObject.CostUnit) {
				'^cpu'     {$LicCostUnit = 'CPU'; Break}
				'^vm'      {$LicCostUnit = 'VM'; Break}
				'server'   {$LicCostUnit = 'SRV'; Break}
				Default    {$LicCostUnit = $InputObject.CostUnit}
			
			}
			
			$ProductFullVersion = $InputObject.Name + ' [' + $InputObject.Used + '/' + $InputObject.Total + $LicCostUnit + ']'
			
			$Properties = [ordered]@{
				ProductName = $InputObject.LicenseKey
				ProductType = $ProductType
				FullVersion = $ProductFullVersion
				Version     = $ProductVersion
			}
		}
	Catch
		{
			$Properties = [ordered]@{
				ProductName = $InputObject.LicenseKey
				ProductType = $ProductTypeName
				FullVersion = 'Unknown'
				Version     = [version]'0.0'
			}
		}
	Finally
		{
			$Object = New-Object PSObject -Property $Properties
			If ($InputObject.EditionKey -ne 'eval') {$Object}
		}
		
	} #EndFunction Get-VersionLicenseKey
	
}

Process {

	If ($PSCmdlet.ParameterSetName -eq 'VIO') {
		Foreach ($obj in $VIObject) {
			If     ($obj -is [VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost])                  {Get-VersionVMHostImpl -InputObject $obj}
			ElseIf ($obj -is [VMware.Vim.HostSystem])                                                  {Get-VersionVMHostView -InputObject $obj}
			ElseIf ($obj -is [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine])          {Get-VersionVM -InputObject $obj}
			ElseIf ($obj -is [VMware.VimAutomation.Vds.Types.V1.VmwareVDSwitch])                       {Get-VersionVDSwitch -InputObject $obj}
			ElseIf ($obj -is [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.VmfsDatastore]) {Get-VersionDatastore -InputObject $obj}
			Else   {Write-Warning "Not supported object type"}
		}
	}
	ElseIf ($PSCmdlet.ParameterSetName -eq 'VC') {
		If ($global:DefaultVIServers.Length) {Foreach ($obj in $global:DefaultVIServers) {Get-VersionVCenter -InputObject $obj}}
		Else {Write-Warning "Please use 'Connect-VIServer' cmdlet to connect to VCenter servers or ESXi hosts."}
		Get-VersionPowerCLi
	}
	ElseIf ($PSCmdlet.ParameterSetName -eq 'LIC') {
		If ($global:DefaultVIServers.Length) {Foreach ($obj in ((Get-View (Get-View ServiceInstance).Content.LicenseManager).Licenses)) {Get-VersionLicenseKey -InputObject $obj}}
		Else {Write-Warning "Please use 'Connect-VIServer' cmdlet to connect to VCenter servers or ESXi hosts."}
	}
}

End {}

} #EndFunction Get-Version

Function Search-Datastore {

<#
.SYNOPSIS
	Search files on a VMware Datastore.
.DESCRIPTION
	This cmdlet searches files on ESXi hosts' Datastores.
.PARAMETER Datastore
	ESXi host Datastore(s).
.PARAMETER FileName
	File name pattern, the default is to search all files (*).
.PARAMETER FileType
	File type to search, the default is to search [.vmdk] or [.iso] files.
.PARAMETER VerboseDatastoreName
	Sends Datastore name to the command line after processing.
.EXAMPLE
	PS C:\> Get-Datastore |Search-Datastore
	Search all [*.vmdk] and [*.iso] files on all Datastores.
.EXAMPLE
	PS C:\> Get-Datastore 'cloud*' |Search-Datastore -FileType VmdkOnly
	Search all [*.vmdk] files on group of Datastores.
.EXAMPLE
	PS C:\> Get-DatastoreCluster 'backup' |Get-Datastore |Search-Datastore -FileName 'win' -FileType IsoOnly -VerboseDatastoreName
	Search [*win*.iso] files on all SDRS cluster members. Verbose each Datastore name.
.EXAMPLE
	PS C:\> 'localssd' |Search-Datastore -FileName 'vm1*' -FileType All |Format-Table -AutoSize
	Search the specific VM related files [vm1*.*] on the local Datastore [localssd].
.EXAMPLE
	PS C:\> $report = Get-DatastoreCluster 'test' |Get-Datastore |Search-Datastore -FileType VmdkOnly -VerboseDatastoreName
	PS C:\> $report |? {$_.DaysInactive -gt 7}
	PS C:\> $report |sort DaysInactive |epcsv -notype -Encoding UTF8 'C:\reports\Test.csv'
	Save the search results to a variable for future manipulations (queries, export or comparison).
.INPUTS
	[VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.VmfsDatastore[]]
	[VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.NasDatastore[]]
	[System.String[]]
	Datastore objects, returtned by 'Get-Datastore' cmdlet or Datastore names.
.OUTPUTS
	[System.Management.Automation.PSCustomObject] PSObject collection.
.NOTES
	Author       ::	Roman Gelman.
	Version 1.0  ::	09-Aug-2016  :: [Release].
	Version 1.1  ::	19-Sep-2016  ::
	[Bugfix] Some SAN as NetApp return `*-flat.vmdk` files in the search. Such files were recognized as orphaned.
	[Change] `Changed Block Tracking Disk` file type was renamed to `CBT Disk`.
.LINK
	http://www.ps1code.com/single-post/2016/08/21/Browse-VMware-Datastores-with-PowerCLi
#>

[CmdletBinding()]
[Alias("Search-ViMDatastore")]

Param (
	[Parameter(Mandatory,Position=0,ValueFromPipeline)]
	$Datastore
	,
	[Parameter(Mandatory=$false,Position=1)]
		[Alias("FileNamePattern")]
	[string]$FileName = "*"
	,
	[Parameter(Mandatory=$false,Position=2)]
		[ValidateSet("Vmdk&Iso","VmdkOnly","IsoOnly","All")]
		[Alias("FileExtension")]
	[string]$FileType = 'Vmdk&Iso'
	,
	[Parameter(Mandatory=$false,Position=3)]
	[switch]$VerboseDatastoreName
	
)

Begin {

	$i = 0
	$Now = [datetime]::Now
	$rgxFileExt = '^(?<FileName>.+)\.(?<Ext>.+)$'
	
	Write-Progress -Activity "Generating Used Disks list" -Status "In progress ..."
	$UsedDisks = Get-View -ViewType VirtualMachine |% {$_.Layout} |% {$_.Disk} |% {$_.DiskFile}
	Write-Progress -Activity "Completed" -Completed
	
	$FileTypes = @{
		'dumpfile'='ESXi Coredump';
		'iso'='CD/DVD Image';
		'vmdk'='Virtual Disk';
		'vmtx'='Template';
		'vmx'='VM Config';
		'lck'='Config Lock';
		'vmx~'='Config Backup';
		'vmxf'='Supplemental Config';
		'vmsd'='Snapshot Metadata';
		'vmsn'='Snapshot Memory';
		'vmss'='Suspended State';
		'vmem'='Paging';
		'vswp'='Swap'
		'nvram'='BIOS State';
		'log'='VM Log';
		''='Unknown'
	}
	
	If ($FileName -notmatch '\*') {$FileName = "*$FileName*"}
	
	Switch ($FileType) {
		'Vmdk&Iso' {$FilePattern = @(($FileName+'.vmdk'),($FileName+'.iso')); Break}
		'VmdkOnly' {$FilePattern = @(($FileName+'.vmdk')); Break}
		'IsoOnly'  {$FilePattern = @(($FileName+'.iso')); Break}
		'All'      {$FilePattern = @(($FileName+'.*'))}
	}
	
} #EndBegin

Process {

	If     ($Datastore -is [string])                                                                 {$DsView = Get-View -ViewType Datastore |? {$_.Name -eq $Datastore}}
	ElseIf ($Datastore -is [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.VmfsDatastore]) {$DsView = Get-View -VIObject $Datastore}
	ElseIf ($Datastore -is [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.NasDatastore])  {$DsView = Get-View -VIObject $Datastore}
	Else                                                                                             {Throw "Not supported object type"}

	If ($DsView) {
	
		$i += 1
	
		$DsCapacityGB = $DsView.Summary.Capacity/1GB

		Write-Progress -Activity "Datastore Browser is working now ..." `
		-Status ("Searching for files on Datastore [$($DsView.Name)]") `
		-CurrentOperation ("Search criteria [" + ($FilePattern -join (', ')) + "]")

		$fileQueryFlags = New-Object VMware.Vim.FileQueryFlags
		$fileQueryFlags.FileSize     = $true
		$fileQueryFlags.FileType     = $true
		$fileQueryFlags.Modification = $true

		$searchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
		$searchSpec.Details          = $fileQueryFlags
		$searchSpec.MatchPattern     = $FilePattern
		$searchSpec.SortFoldersFirst = $true

		$DsBrowser    = Get-View $DsView.Browser
		$rootPath     = "[$($DsView.Name)]"
		$searchResult = $DsBrowser.SearchDatastoreSubFolders($rootPath, $searchSpec)

		Foreach ($folder in $searchResult) {
		 	Foreach ($fileResult in $folder.File) {
				If ($fileResult.Path) {
					
					If ($fileResult.FileSize/1GB -lt 1) {$Round = 3} Else {$Round = 0}
					$SizeGiB = [Math]::Round($fileResult.FileSize/1GB, $Round)
					
					$File = [regex]::Match($fileResult.Path, $rgxFileExt)
					$FileBody = $File.Groups['FileName'].Value
					$ShortExt = $File.Groups['Ext'].Value
					
					If ($FileTypes.ContainsKey($ShortExt)) {$LongExt = $FileTypes.$ShortExt} Else {$LongExt = '.'+$ShortExt.ToUpper()}
					
					If ($ShortExt -eq 'vmdk') {
						If ($FileBody -match '-ctk$') {$LongExt = 'CBT Disk'}
						Else {
							If ($FileBody -match '-(\d{6}|delta)$') {$LongExt = 'Snapshot Disk'}
							If ($UsedDisks -notcontains ($folder.FolderPath + $fileResult.Path) -and $FileBody -notmatch '-flat$') {$LongExt = 'Orphaned '+$LongExt}
						}
					}
					
				    $Properties = [ordered]@{
					    Datastore    = $DsView.Name
					    Folder       = [regex]::Match($folder.FolderPath, '\]\s(?<Folder>.+)/').Groups[1].Value
					    File         = $fileResult.Path
						FileType     = $LongExt
					    SizeGB       = $SizeGiB
						SizeBar      = New-PercentageBar -Value $SizeGiB -MaxValue $DsCapacityGB
					    Modified     = ([datetime]$fileResult.Modification).ToString('dd-MMM-yyyy HH:mm')
						DaysInactive = (New-TimeSpan -Start ($fileResult.Modification) -End $Now).Days
					}
					$Object = New-Object PSObject -Property $Properties
					$Object
				}
		 	}
		}
		If ($PSBoundParameters.ContainsKey('VerboseDatastoreName')) {"Datastore N" + [char][byte]186 + "$i [$($DsView.Name)] completed" |Out-Host}
	}
} #EndProcess

End {Write-Progress -Activity "Completed" -Completed}

} #EndFunction Search-Datastore

Function Compare-VMHost {

<#
.SYNOPSIS
	Compare two or more ESXi hosts on different properties.
.DESCRIPTION
	This cmdlet can compare two or more ESXi hosts on different criteria.
.PARAMETER ReferenceVMHost
	Reference ESXi host.
.PARAMETER DifferenceVMHost
	Difference ESXi host.
.PARAMETER Compare
	What to compare.
.PARAMETER Truncate
	Try to truncate ESXi hostname.
.PARAMETER ColorOutput
	Redirect color output to the console.
.EXAMPLE
	PS C:\> Get-VMHost 'esx2.*' |Compare-VMHost -ReferenceVMHost (Get-VMHost 'esx1.*') -Compare ScsiDevice
.EXAMPLE
	PS C:\> Get-VMHost 'esx2[78].*' |Compare-VMHost -ReferenceVMHost (Get-VMHost 'esx21.*') -Compare SharedDatastore
	Compare shared datastores of two VMHosts [esx27],[esx28] with the reference VMHost [esx21].
.EXAMPLE
	PS C:\> Get-VMHost 'esx2.*' |Compare-VMHost -ReferenceVMHost (Get-VMHost 'esx1.*') -Compare Portgroup -Truncate -ColorOutput
	Compare portgroups between two hosts, truncate hostnames and redirect color output to the console.
.INPUTS
	[VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost] VMHost objects, returned by `Get-VMHost` cmdlet.
.OUTPUTS
	[System.Management.Automation.PSCustomObject] PSObject collection.
.NOTES
	Author      :: Roman Gelman
	Version 1.0 :: 26-Sep-2016 :: [Release]
.LINK
	http://www.ps1code.com/single-post/2016/09/26/Compare-two-or-more-ESXi-hosts-with-PowerCLi
#>

[Alias("Compare-ViMVMHost")]

Param (

	[Parameter(Mandatory,Position=1,HelpMessage="Reference VMHost")]
		[Alias("ReferenceESXi")]
	[VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost]$ReferenceVMHost
	,
	[Parameter(Mandatory,Position=2,ValueFromPipeline,HelpMessage="Difference VMHosts collection")]
		[Alias("DifferenceESXi","DifferenceVMHosts")]
	[VMware.VimAutomation.ViCore.Types.V1.Inventory.VMHost[]]$DifferenceVMHost
	,
	[Parameter(Mandatory=$false,Position=3,HelpMessage="Compare VMHosts on this property")]
		[ValidateSet("ScsiDevice","ScsiLun","Datastore","SharedDatastore","Portgroup")]
	[string]$Compare = 'ScsiLun'
	,
	[Parameter(Mandatory=$false,Position=4,HelpMessage="Try to truncate a VMHost name from its FQDN")]
		[Alias("TruncateVMHostName")]
	[switch]$Truncate
	,
	[Parameter(Mandatory=$false,Position=5,HelpMessage="Send colorized output to the console")]
		[Alias("Color")]
	[switch]$ColorOutput
)

Begin {

	$ErrorActionPreference = 'Stop'
	$Width = 3

	Try
	{
		Switch -exact ($Compare) {
		
			'ScsiLun'
			{
				$RefHost = (Get-ScsiLun -VmHost $ReferenceVMHost -LunType 'disk' |
				select @{N='LUN';E={([regex]::Match($_.RuntimeName, ':L(\d+)$').Groups[1].Value) -as [int]}} |
				sort LUN).LUN
				$Length = 'ScsiLun'.Length
				Break
			}
			'ScsiDevice'
			{
				$RefHost = (Get-ScsiLun -VmHost $ReferenceVMHost -LunType 'disk' |
				select CanonicalName |sort CanonicalName).CanonicalName
				$Length = 'ScsiDevice'.Length
				$Width = $Width + 1
				Break
			}
			'Datastore'
			{
				$RefHost = ($ReferenceVMHost |Get-Datastore |select Name |sort Name).Name
				$Length = 'Datastore'.Length
				$Width = $Width - 1
				Break
			}
			'SharedDatastore'
			{
				$RefHost = ($ReferenceVMHost |Get-Datastore |? {$_.ExtensionData.Summary.MultipleHostAccess} |select Name |sort Name).Name
				$Length = 'SharedDatastore'.Length
				$Width = $Width - 1
				Break
			}
			'Portgroup'
			{
				$RefHost = (($ReferenceVMHost).NetworkInfo.ExtensionData.Portgroup).Spec.Name
				$Length = 'Portgroup'.Length
				$Width = $Width - 1
			}
		} #EndSwitch
		
		### Write a header to the console ###
		If ($ColorOutput) {
			$Tab = "`t"*$Width
			$Minus = "-"*$Length
			Write-Host ("`n$Compare$Tab"+'VMHost') -ForegroundColor Green
			Write-Host ("$Minus$Tab"+'-'*6) -ForegroundColor Green
		}
	}
	Catch
	{
		"{0}" -f $Error.Exception.Message
	}
}

Process {

	Try
	{
		Switch -exact ($Compare) {
		
			'ScsiLun'
			{
				$DifHost = (Get-ScsiLun -VmHost $DifferenceVMHost -LunType 'disk' |
				select @{N='LUN';E={([regex]::Match($_.RuntimeName, ':L(\d+)$').Groups[1].Value) -as [int]}} |
				sort LUN).LUN
				Break
			}
			'ScsiDevice'
			{
				$DifHost = (Get-ScsiLun -VmHost $DifferenceVMHost -LunType 'disk' |
				select CanonicalName |sort CanonicalName).CanonicalName
				Break
			}
			'Datastore'
			{
				$DifHost = ($DifferenceVMHost |Get-Datastore |select Name |sort Name).Name
				Break
			}
			'SharedDatastore'
			{
				$DifHost = ($DifferenceVMHost |Get-Datastore |? {$_.ExtensionData.Summary.MultipleHostAccess} |select Name |sort Name).Name
				Break
			}
			'Portgroup'
			{
				$DifHost = (($DifferenceVMHost).NetworkInfo.ExtensionData.Portgroup).Spec.Name
			}
		} #EndSwitch
		
		$diffObj = Compare-Object -ReferenceObject $RefHost -DifferenceObject $DifHost -IncludeEqual:$false -CaseSensitive
		Foreach ($diff in $diffObj) {
			If ($diff.SideIndicator -eq '=>') {
				$diffOwner  = $DifferenceVMHost.Name
				$Reference  = $false
				$Difference = ''
			}
			Else {
				$diffOwner  = $ReferenceVMHost.Name
				$Reference  = $true
				$Difference = $DifferenceVMHost.Name
			}
			
			If ($Truncate) {
				$diffOwner  = [regex]::Match($diffOwner, '^(.+?)(\.|$)').Groups[1].Value
				$Difference = [regex]::Match($Difference, '^(.+?)(\.|$)').Groups[1].Value
			}
			
			$Properties = [ordered]@{
				$Compare   = $diff.InputObject
				VMHost     = $diffOwner
				Reference  = $Reference
				Difference = $Difference
			}
			$Object = New-Object PSObject -Property $Properties
			
			### Return resultant object ###
			If ($ColorOutput) {
				If (($Object.$Compare).Length -lt 8) {$Tabs = "`t"*3} ElseIf (8..15 -contains ($Object.$Compare).Length) {$Tabs = "`t"*2} Else {$Tabs = "`t"}
				$Output = "$($Object.$Compare)$Tabs$diffOwner"
				If ($Reference) {Write-Host $Output -ForegroundColor Yellow}
				Else            {Write-Host $Output -ForegroundColor Gray}
			} Else {$Object}
		}
	}
	Catch
	{
		"{0}" -f $Error.Exception.Message
	}
	
} #EndProcess

End {If ($ColorOutput) {"`r"}}

} #EndFunction Compare-VMHost

Function Move-Template2Datastore {

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
.NOTES
	Author      :: Roman Gelman
	Shell       :: Tested on PowerShell 5.0/5.1|PowerCLi 6.5
	Platform    :: Tested on vSphere 5.5/6.0|VCenter 5.5U2/VCSA 6.0U1
	Requirement :: ESXi Hosts where Templates are registered must be HA/DRS Cluster members. PowerShell 3.0+
	Version 1.0 :: 14-Dec-2016 :: [Release]
.LINK
	http://www.ps1code.com/single-post/2016/12/19/How-to-migrate-VMware-VM-Templates-to-another-Datastore-by-PowerCLi
#>

[CmdletBinding(DefaultParameterSetName='DS')]
[Alias("Move-ViMTemplate2Datastore")]
[OutputType([PSCustomObject])]

Param (
	[Parameter(Mandatory,ValueFromPipeline)]
		[Alias("VMTemplate","Templates")]
	[VMware.VimAutomation.ViCore.Types.V1.Inventory.Template[]]$Template
	,
	[Parameter(Mandatory,Position=0,ParameterSetName='DS')]
	$Datastore
	,
	[Parameter(Mandatory,Position=0,ParameterSetName='DSC')]
	[VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.DatastoreCluster]$DatastoreCluster
)

Begin {
	$ErrorActionPreference = 'Stop'
	If ($PSCmdlet.ParameterSetName -eq 'DS') {
		If ($Datastore -isnot [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.VmfsDatastore] `
		-and $Datastore -isnot [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.NasDatastore]) {Throw "Unsupported Datastore type"}
	}
} #EndBegin

Process {
	Try
	{
		$null = . {
		
			### Get random Datastore from the DatastoreCluster ###
			If ($PSCmdlet.ParameterSetName -eq 'DSC') {
				$Datastore = Get-DatastoreCluster $DatastoreCluster |Get-Datastore |sort {Get-Random} |select -First 1
			}
			
			### Convert the Template to a VM ###
			$poolMoref = (Get-ResourcePool -Location (Get-VMHost -Id $Template.HostId |Get-Cluster) -Name Resources).Id
			$hostMoref = $Template.HostId
			$ViewTemplate = Get-View -VIObject $Template
			$ViewTemplate.MarkAsVirtualMachine($poolMoref,$hostMoref)
			$VM = Get-VM -Name $Template.Name
			
			### Initialize SVMotion Task ###
			$ViewVM = Get-View -VIObject $VM
			$spec = New-Object -TypeName 'VMware.Vim.VirtualMachineRelocateSpec'
			$spec.Datastore = New-Object -TypeName 'VMware.Vim.ManagedObjectReference'
			$spec.Datastore = $Datastore.Id
			$priority = [VMware.Vim.VirtualMachineMovePriority]'defaultPriority'
			$TaskMoref = $ViewVM.RelocateVM_Task($spec,$priority)

			$ViewTask = Get-View $TaskMoref
			For ($i=1; $i -lt [int32]::MaxValue; $i++) {
				If ("running","queued" -contains $ViewTask.Info.State) {
					$ViewTask.UpdateViewData("Info")
					If ($ViewTask.Info.Progress -ne $null) {
						Write-Progress -Activity "Migrating Template ..." -Status "Template [$($VM.Name)]" `
						-CurrentOperation "Datastore [$($Datastore.Name)]" `
						-PercentComplete $ViewTask.Info.Progress -ErrorAction SilentlyContinue
						Start-Sleep -Seconds 3
					}
				} Else {Write-Progress -Activity "Completed" -Completed; Break}
			}
			If ($ViewTask.Info.State -eq "error") {
				$ViewTask.UpdateViewData("Info.Error")
				$ViewTask.Info.Error.Fault.FaultMessage |% {$_.Message}
			}
			
			### Convert the VM back to the Template ###
			$ViewVM.MarkAsTemplate()
			
			$ErrorMsg = $null
		}
	}
	Catch {$ErrorMsg = "{0}" -f $Error.Exception.Message}
	
	$Properties = [ordered]@{
		Template  = $Template.Name
		Datastore = $Datastore.Name
		Error     = $ErrorMsg
	}
	$Object = New-Object PSObject -Property $Properties
	$Object
	
} #EndProcess

End {}

} #EndFunction Move-Template2Datastore

Function Read-VMHostCredential {

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
	Author      :: Roman Gelman
	Requirement :: PowerShell 3.0+
	Version 1.0 :: 27-Dec-2016 :: [Release]
.LINK
	https://github.com/rgel/Azure/blob/master/New-SecureCred.ps1
#>

Param (
	[Parameter(Mandatory=$false,Position=0)]
		[ValidateNotNullorEmpty()]
		[ValidateScript({Test-Path $_ -PathType Leaf})]
	[string]$CredFile = "$(Split-Path $PROFILE)\esx.cred"
	,
	[Parameter(Mandatory=$false)]
	[switch]$User
)

	$Login = 'root'

	If (Test-Path $CredFile -PathType Leaf) {
		$SecurePwd = gc $CredFile |ConvertTo-SecureString
		Try
		{
			$immCred = New-Object -TypeName 'System.Management.Automation.PSCredential'($Login,$SecurePwd) -EA Stop
			If ($User) {return $Login}
			Else       {return $immCred.GetNetworkCredential().Password}
		}
		Catch {return $null}
	} Else {return $null}

} #EndFunction Read-VMHostCredential

Function Connect-VMHostPutty {

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
	Author      :: Roman Gelman
	Requirement :: PowerShell 3.0+
	Version 1.0 :: 27-Dec-2016 :: [Release]
	Version 1.1 :: 04-Jan-2017 :: [Bugfix]  The `putty` Alias was not created during Module import.
	
.LINK
	http://www.ps1code.com/single-post/2016/12/27/PowerShell-and-putty-%E2%80%93-better-together
#>

[Alias("Connect-ViMVMHostPutty","putty")]

Param (
	[Parameter(Mandatory,ValueFromPipeline)]
	[string]$VMHost
	,
	[Parameter(Mandatory=$false)]
		[ValidateNotNullorEmpty()]
		[ValidateScript({Test-Path $_ -PathType Leaf})]
	[string]$PuttyExec = "$(Split-Path $PROFILE)\putty.exe"
)

	$PuttyPwd   = Read-VMHostCredential
	$PuttyLogin = Read-VMHostCredential -User
	If ($PuttyPwd) {&$PuttyExec -ssh $PuttyLogin@$VMHost -pw $PuttyPwd}
	
} #EndFunction Connect-VMHostPutty

Function Set-MaxSnapshotNumber {

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
	PowerCLI C:\> Get-VM $VMName |Set-MaxSnapshotNumber
	Set default value.
.EXAMPLE
	PowerCLI C:\> Get-VM |Set-MaxSnapshotNumber -Report
	Get current set value for all VM in the inventory.
.EXAMPLE
	PowerCLI C:\> Get-VM |Set-MaxSnapshotNumber -Report |? {$_.MaxSnapshot -eq 0}
	Get VM with snapshots prohibited.
.EXAMPLE
	PowerCLI C:\> Get-VM $VMName |Set-MaxSnapshotNumber -Number 496
	Set maximum supported value.
.EXAMPLE
	PowerCLI C:\> Get-VM |? {$_.Name -like 'win*'} |Set-MaxSnapshotNumber 0 -Confirm:$false
	Prohibit snapshots for multiple VM without confirmation.
.NOTES
	Idea        :: William Lam
	Author      :: Roman Gelman
	Shell       :: Tested on PowerShell 5.0|PowerCLi 6.5
	Platform    :: Tested on vSphere 5.5/6.0|VCenter 5.5U2/VCSA 6.0U1
	Requirement :: PowerShell 3.0+
	Version 1.0 :: 24-Jan-2017 :: [Release]
.LINK
	https://www.ps1code.com/single-post/2017/01/24/How-to-control-maximum-number-of-VMware-snapshots-with-PowerCLi
#>

[CmdletBinding(DefaultParameterSetName="SET",ConfirmImpact='High',SupportsShouldProcess=$true)]
[Alias("Set-ViMMaxSnapshotNumber","maxsnap")]
[OutputType([PSCustomObject])]

Param (
	[Parameter(Mandatory,ValueFromPipeline)]
	[VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]]$VM
	,
	[Parameter(Mandatory=$false,Position=0,ParameterSetName='SET')]
		[ValidateRange(0,496)]
		[Alias("Quantity")]
	[uint16]$Number = 31
	,
	[Parameter(Mandatory,Position=0,ParameterSetName='GET')]
		[Alias("ReportOnly")]
	[switch]$Report
)

Begin {
	$ErrorActionPreference = 'Stop'
	$WarningPreference     = 'SilentlyContinue'
	$AdvSetting = 'snapshot.maxSnapshots'
	$NotSetValue = 'NotSet'
} #EndBegin

Process {

	$ShouldMessage = Switch ($Number) {
		31      {"Set maximum allowed snapshot number to the default [$Number]"; Break}
		0       {"Prohibit taking snapshots at all!"; Break}
		496     {"Set maximum allowed snapshot number to the maximum possible [$Number]"; Break}
		Default {"Set maximum allowed snapshot number to [$Number]"}
	}

	If ($PSCmdlet.ParameterSetName -eq 'SET') {

		If ($PSCmdlet.ShouldProcess($VM.Name, $ShouldMessage)) {
			Try
			{
				$AdvancedSettingImplBefore = $VM |Get-AdvancedSetting -Name $AdvSetting
				$CurrentSetting = If ($AdvancedSettingImplBefore) {$AdvancedSettingImplBefore.Value} Else {$NotSetValue}
				$AdvancedSettingImplAfter  = $VM |New-AdvancedSetting -Name $AdvSetting -Value $Number -Force -Confirm:$false
				$Properties = [ordered]@{
					VM              = $VM.Name
					AdvancedSetting = $AdvSetting
					PreviousValue   = $CurrentSetting
					CurrentValue    = $AdvancedSettingImplAfter.Value
				}
				$Object = New-Object PSObject -Property $Properties
				$Object
			} Catch {"{0}" -f $Error.Exception.Message}
		}
	} Else {
	
		Try
		{
			$AdvancedSettingImplBefore = $VM |Get-AdvancedSetting -Name $AdvSetting
			$CurrentSetting = If ($AdvancedSettingImplBefore) {$AdvancedSettingImplBefore.Value} Else {$NotSetValue}
			$Properties = [ordered]@{
				VM          = $VM.Name
				MaxSnapshot = $CurrentSetting
			}
			$Object = New-Object PSObject -Property $Properties
			$Object
		} Catch {"{0}" -f $Error.Exception.Message}
	}
} #EndProcess

End {}

} #EndFunction Set-MaxSnapshotNumber

Filter Convert-MoRef2Name {
	
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
	PowerCLI C:\> Get-VMHost 'esx1.*' |select Name,@{N='Cluster';E={$_.ParentId |Convert-MoRef2Name}}
	Get VMHost's parent container name from VMHosts's property `ParentId`.
	It may be HA/DRS cluster name, Datacenter name or Folder name.
.EXAMPLE
	PowerCLI C:\> Get-VDSwitch |select Name,@{N='Portgroups';E={'[ ' + ((($_ |select -expand ExtensionData).Portgroup |Convert-MoRef2Name |sort) -join ' ][ ') + ' ]'}}
	Expand all! Portgroup names from Distributed VSwitch's property `ExtensionData.Portgroup`.
.EXAMPLE
	PowerCLI C:\> Get-Datastore 'test*' |sort Name |select Name,@{N='ConnectedHosts';E={'[' + ((($_ |select -expand ExtensionData).Host.Key |Convert-MoRef2Name -ShortName |sort) -join '] [') + ']' }}
	Expand all connected VMHost names from Datastore's property `ExtensionData.Host.Key`.
	Truncate VMHost's hostname from FQDN if it is possible.
.INPUTS
	[System.String] VI Object Id/MoRef.
.OUTPUTS
	[System.String] VI Object name.
.NOTES
	Author      :: Roman Gelman @rgelman75
	Version 1.0 :: 09-Sep-2016  :: [Release]
	Version 1.1 :: 18-Apr-2017  :: [Change] :: Empty string returned on error
.LINK
	http://ps1code.com
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
	Version 1.0 :: 23-Apr-2017 :: [Release]
.LINK
	http://ps1code.com
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
