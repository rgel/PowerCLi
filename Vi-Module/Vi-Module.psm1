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
	[VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl[]] Get-VM collection.
.OUTPUTS
	[System.Management.Automation.PSCustomObject] PSObject collection.
.NOTES
	Author: Roman Gelman.
	Version 1.0 :: 16-Oct-2015 :: Release
	Version 1.1 :: 03-Dec-2015 :: Bugfix :: Error message appear while VML mismatch,
	when the VML identifier does not match for an RDM on two or more ESXi hosts.
	VMware [KB2097287].
.LINK
	http://goo.gl/3wO4pi
#>

[CmdletBinding()]

Param (

	[Parameter(Mandatory=$false,Position=1,ValueFromPipeline=$true,HelpMessage="VM's collection, returned by Get-VM cmdlet")]
		[ValidateNotNullorEmpty()]
		[Alias("VM")]
	[VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl[]]$VMs = (Get-VM)

)

Begin {

	$Object    = @()
	$regxVMDK  = '^\[(?<Datastore>.+)\]\s(?<Filename>.+)$'
	$regxLUNID = ':L(?<LUNID>\d+)$'
}

Process {
	
	Foreach ($vm in ($VMs |Get-View)) {
		Foreach ($dev in $vm.Config.Hardware.Device) {
		    If (($dev.GetType()).Name -eq "VirtualDisk") {
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
New-Alias -Name Get-ViMRDM -Value Get-RDM -Force:$true

Function Convert-VmdkThin2EZThick {

<#
.SYNOPSIS
	Inflate thin virtual disks.
.DESCRIPTION
	This function convert all Thin Provisioned VM's disks to type 'Thick Provision Eager Zeroed'.
.PARAMETER VM
	VM's collection, returned by Get-VM cmdlet.
.EXAMPLE
	C:\PS> Get-VM VM1 |Convert-VmdkThin2EZThick
.EXAMPLE
	C:\PS> Get-VM VM1,VM2 |Convert-VmdkThin2EZThick -Confirm:$false |sort VM,Datastore,VMDK |ft -au
.INPUTS
	Get-VM collection.
	[VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl[]]
.OUTPUTS
	PSObject collection.
.NOTES
	Author: Roman Gelman.
.LINK
	http://goo.gl/cVpTpO
#>

[CmdletBinding(ConfirmImpact='High',SupportsShouldProcess=$true)]

Param (

	[Parameter(Mandatory=$true,Position=1,ValueFromPipeline=$true,HelpMessage="VM's collection, returned by Get-VM cmdlet")]
		[ValidateNotNullorEmpty()]
		[Alias("VM")]
	[VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl[]]$VMs

)

Begin {

	$Object   = @()
	$regxVMDK = '^\[(?<Datastore>.+)\]\s(?<Filename>.+)$'

}

Process {
	
	Foreach ($vm in ($VMs |Get-View)) {
	
		### Ask confirmation to proceed if VM is PoweredOff ###
		If ($vm.Runtime.PowerState -eq 'poweredOff' -and $PSCmdlet.ShouldProcess("VM [$($vm.Name)]","Convert all Thin Provisioned VMDK to Type: 'Thick Provision Eager Zeroed'")) {
		
			### Get ESXi object where $vm is registered ###
			$esx = Get-View $vm.Runtime.Host
			
			### Get Datacenter object where $vm is registered ###
			$parentObj = Get-View $vm.Parent
		    While ($parentObj -isnot [VMware.Vim.Datacenter]) {$parentObj = Get-View $parentObj.Parent}
		    $datacenter       = New-Object VMware.Vim.ManagedObjectReference
			$datacenter.Type  = 'Datacenter'
			$datacenter.Value = $parentObj.MoRef.Value
		   
			Foreach ($dev in $vm.Config.Hardware.Device) {
			    If (($dev.GetType()).Name -eq "VirtualDisk") {
					If ($dev.Backing.ThinProvisioned -and $dev.Backing.Parent -eq $null) {
					
			        	$sizeGB = [math]::Round(($dev.CapacityInKB / 1MB), 1)
						
						### Invoke 'Inflate virtual disk' task ###
						$ViDM      = Get-View -Id 'VirtualDiskManager-virtualDiskManager'
						$taskMoRef = $ViDM.InflateVirtualDisk_Task($dev.Backing.FileName, $datacenter)
						$task      = Get-View $taskMoRef
						
						### Show task progress ###
						For ($i=1;$i -lt [int32]::MaxValue;$i++) {
							If ("running","queued" -contains $task.Info.State) {
								$task.UpdateViewData("Info")
								If ($task.Info.Progress -ne $null) {
									Write-Progress -Activity "Inflate virtual disk task is in progress ..." -Status "VM - $($vm.Name)" `
									-CurrentOperation "$($dev.DeviceInfo.Label) - $($dev.Backing.FileName) - $sizeGB GB" `
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
						$tCompleteTime = [math]::Round((New-TimeSpan -Start $tStart -End $tEnd).TotalMinutes, 1)
						
						### Expand 'Datastore' and 'VMDK' from file path ###
						$null = $dev.Backing.FileName -match $regxVMDK
						
						$Properties = [ordered]@{
							VM           = $vm.Name
							VMHost       = $esx.Name
							Datastore    = $Matches.Datastore
							VMDK         = $Matches.Filename
							HDLabel      = $dev.DeviceInfo.Label
							HDSizeGB     = $sizeGB
							Result       = $tResult
							StartTime    = $tStart
							CompleteTime = $tEnd
							TimeMin      = $tCompleteTime
						}
						$Object = New-Object PSObject -Property $Properties
						$Object
					}
				}
			}
			$vm.Reload()
		}
	}
}

End {
	Write-Progress -Completed $true -Status "Please wait"
}

} #EndFunction Convert-VmdkThin2EZThick
New-Alias -Name Convert-ViMVmdkThin2EZThick -Value Convert-VmdkThin2EZThick -Force:$true

Function Find-VcVm {

#requires -version 3.0

<#
.SYNOPSIS
	Search VC's VM throw direct connection to group of ESXi Hosts.
.DESCRIPTION
	This script generate list of ESXi Hosts with common suffix in name,
	e.g. (esxprod1,esxprod2, ...) or (esxdev01,esxdev02, ...) etc. and
	search VCenter's VM throw direct connection to this group of ESXi Hosts.
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
	C:\PS> .\Find-VC.ps1 vc1 esxprod 1 20 -AddZero
.EXAMPLE
	C:\PS> .\Find-VC.ps1 -VC vc1 -HostSuffix esxdev -PostfixEnd 6
.EXAMPLE
	C:\PS> .\Find-VC.ps1 vc1 esxprod |fl
.NOTES
	Author: Roman Gelman.
.OUTPUTS
	PSCustomObject with two Properties: VC,VMHost or $null.
.LINK
	http://rgel75.wix.com/blog
#>

Param (

	[Parameter(Mandatory=$true,Position=1,HelpMessage="vCenter's VM Name")]
		[Alias("vCenter","VcVm")]
	[System.String]$VC
	,
	[Parameter(Mandatory=$true,Position=2,HelpMessage="ESXi Hosts' common suffix")]
		[Alias("VMHostSuffix","ESXiSuffix")]
	[System.String]$HostSuffix
	,
	[Parameter(Mandatory=$false,Position=3,HelpMessage="ESXi Hosts' postfix number start")]
		[ValidateRange(1,98)]
		[Alias("PostfixFirst","Start")]
	[Int]$PostfixStart = 1
	,
	[Parameter(Mandatory=$false,Position=4,HelpMessage="ESXi Hosts' postfix number end")]
		[ValidateRange(2,99)]
		[Alias("PostfixLast","End")]
	[Int]$PostfixEnd = 9
	,
	[Parameter(Mandatory=$false,Position=5,HelpMessage="Add ESXi Hosts' postfix leading zero")]
	[Switch]$AddZero = $false
)

Begin {

	Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Scope Session -Confirm:$false |Out-Null
	If ($PostfixEnd -le $PostfixStart) {Throw "PostfixEnd must be greater than PostfixStart"}
}

Process {

	$VMHostName = ''
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
		Connect-VIServer $hosts -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -Credential $cred |select Name,IsConnected |ft -AutoSize
		If ($global:DefaultVIServers.Length -ne 0) {
			$VMHostName = (Get-VM -ErrorAction SilentlyContinue |? {$_.Name -eq $VC} |select -ExpandProperty VMHost).Name
			Disconnect-VIServer -Server '*' -Force -Confirm:$false
		}
	}
}

End {

	If ($VMHostName)	{
		$Properties = [ordered]@{
			VC     = $VC
			VMHost = $VMHostName
		}
		$Object = New-Object PSObject -Property $Properties
		return $Object
	}
	Else {return $null}
}

} #EndFunction Find-VcVm
New-Alias -Name Find-ViMVcVm -Value Find-VcVm -Force:$true

Function Set-PowerCLiTitle {

<#
.SYNOPSIS
	Write connected VI servers info to PowerCLi window title bar.
.DESCRIPTION
	This function write connected VI servers info to PowerCLi window/console title bar [Name :: Product (VCenter/ESXi) ProductVersion].
.EXAMPLE
	C:\PS> Set-PowerCLiTitle
.NOTES
	Author: Roman Gelman.
.LINK
	http://goo.gl/0h97C6
#>

$VIS = $global:DefaultVIServers |sort -Descending ProductLine,Name

If ($VIS) {
	Foreach ($VIObj in $VIS) {
		If ($VIObj.IsConnected) {
			Switch -exact ($VIObj.ProductLine) {
				vpx			{$VIProduct = 'VCenter'; Break}
				embeddedEsx {$VIProduct = 'ESXi'; Break}
				Default		{$VIProduct = $VIObj.ProductLine; Break}
			}
			$Header += "[$($VIObj.Name) :: $VIProduct$($VIObj.Version)] "
		}
	}
} Else {
	$Header = ':: Not connected to Virtual Infra Services ::'
}

$Host.UI.RawUI.WindowTitle = $Header

} #EndFunction Set-PowerCLiTitle
New-Alias -Name Set-ViMPowerCLiTitle -Value Set-PowerCLiTitle -Force:$true

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
	[VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl[]] Objects, returned by Get-VMHost cmdlet.
	[VMware.Vim.HostSystem[]] Objects, returned by Get-View cmdlet.
	[System.String[]] ESXi hostname or FQDN.
.OUTPUTS
	[System.String[]] BIOS/UEFI version and release date.
.NOTES
	Author: Roman Gelman.
.LINK
	https://goo.gl/Yg7mYp
#>

Try
	{
		If     ($_.GetType().Name -eq 'VMHostImpl') {$BiosInfo = ($_ |Get-View).Hardware.BiosInfo}
		ElseIf ($_.GetType().Name -eq 'HostSystem') {$BiosInfo = $_.Hardware.BiosInfo}
		ElseIf ($_.GetType().Name -eq 'String')     {$BiosInfo = (Get-View -ViewType HostSystem -Filter @{"Name" = $_}).Hardware.BiosInfo}
		Else   {Throw "Not supported data type as pipeline"}

		$fVersion = $BiosInfo.BiosVersion -replace ('^-\[|\]-$', $null)
		$fDate    = [Regex]::Match($BiosInfo.ReleaseDate, '(\d{1,2}/){2}\d+').Value
		If ($fVersion) {return "$fVersion [$fDate]"} Else {return $null}
	}
Catch
	{}
} #EndFilter Get-VMHostFirmwareVersion
New-Alias -Name Get-ViMVMHostFirmwareVersion -Value Get-VMHostFirmwareVersion -Force:$true

Function Compare-VMHostSoftwareVib {

<#
.SYNOPSIS
	Compares the installed VIB packages between VMware ESXi Hosts.
.DESCRIPTION
	This function compares the installed VIB packages between reference ESXi Host and
	group of difference/target ESXi Hosts or single ESXi Host.
.PARAMETER ReferenceVMHost
	Reference VMHost.
.PARAMETER DifferenceVMHosts
	Target VMHosts to compare them with the reference VMHost.
.EXAMPLE
	PS C:\> Compare-VMHostSoftwareVib -ReferenceVMHost (Get-VMHost 'esxprd1.*') -DifferenceVMHosts  (Get-VMHost 'esxprd2.*')
	Compare two ESXi hosts.
.EXAMPLE
	PS C:\> Get-VMHost 'esxdev2.*','esxdev3.*' |Compare-VMHostSoftwareVib -ReferenceVMHost (Get-VMHost 'esxdev1.*')
	Compare two target ESXi Hosts with the reference Host.
.EXAMPLE
	PS C:\> Get-Cluster DEV |Get-VMHost |Compare-VMHostSoftwareVib -ReferenceVMHost (Get-VMHost 'esxdev1.*')
	Compare all HA/DRS cluster members with the reference ESXi Host.
.EXAMPLE
	PS C:\> Get-Cluster PRD |Get-VMHost |Compare-VMHostSoftwareVib -ReferenceVMHost (Get-VMHost 'esxhai1.*') |Export-Csv -NoTypeInformation -Path '.\VibCompare.csv'
	Export the comparison report to the file.
.INPUTS
	[VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl[]] Objects, returned by Get-VMHost cmdlet.
.OUTPUTS
	[System.Management.Automation.PSCustomObject] PSObject collection.
.NOTES
	Author: Roman Gelman.
.LINK
	https://goo.gl/Yg7mYp
#>

Param (

	[Parameter(Mandatory,Position=1,HelpMessage="Reference VMHost")]
		[Alias("ReferenceESXi")]
	[VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl]$ReferenceVMHost
	,
	[Parameter(Mandatory,Position=2,ValueFromPipeline,HelpMessage="Difference VMHosts collection")]
		[Alias("DifferenceESXi")]
	[VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl[]]$DifferenceVMHosts
)

Begin {


}

Process {

	 Try 
		{
			$esxcliRef = Get-EsxCli -VMHost $ReferenceVMHost -ErrorAction Stop
			$refVibId  = ($esxcliRef.software.vib.list()).ID 
		}
	Catch
		{
			"{0}" -f $Error.Exception.Message
		}

	Foreach ($esx in $DifferenceVMHosts) {
	
		 Try
			{
				$esxcliDif = Get-EsxCli -VMHost $esx -ErrorAction Stop
				$diffObj   = Compare-Object -ReferenceObject $refVibId -DifferenceObject ($esxcliDif.software.vib.list()).ID -IncludeEqual:$false
				Foreach ($diff in $diffObj) {
					If ($diff.SideIndicator -eq '=>') {$diffOwner = $esx} Else {$diffOwner = $ReferenceVMHost}
					$Properties = [ordered]@{
						VIB    = $diff.InputObject
						VMHost = $diffOwner 
					}
					$Object = New-Object PSObject -Property $Properties
					$Object
				}
			}
		Catch
			{
				"{0}" -f $Error.Exception.Message
			}
	}
}

} #EndFunction Compare-VMHostSoftwareVib
New-Alias -Name Compare-ViMVMHostSoftwareVib -Value Compare-VMHostSoftwareVib -Force:$true

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
	[VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl[]] Objects, returned by Get-VMHost cmdlet.
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
.LINK
	https://goo.gl/Yg7mYp
#>

Param (

	[Parameter(Mandatory=$false,Position=0,ValueFromPipeline=$true)]
		[ValidateNotNullorEmpty()]
	[VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl[]]$Cluster = (Get-Cluster)
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

}
New-Alias -Name Enable-ViMVMHostSSH -Value Enable-VMHostSSH -Force:$true

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
.LINK
	https://goo.gl/Yg7mYp
#>

Param (

	[Parameter(Mandatory=$false,Position=0,ValueFromPipeline=$true)]
		[ValidateNotNullorEmpty()]
	[VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl[]]$Cluster = (Get-Cluster)
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

}
New-Alias -Name Disable-ViMVMHostSSH -Value Disable-VMHostSSH -Force:$true

Export-ModuleMember -Alias '*' -Function '*'
