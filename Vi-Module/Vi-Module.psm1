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
.INPUTS
	Get-VM collection.
	[VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl[]]
.OUTPUTS
	PSObject collection.
.NOTES
	Author: Roman Gelman.
.LINK
	http://rgel75.wix.com/blog
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
					$null = (Get-ScsiLun -VmHost $esx.Name -CanonicalName $esxScsiLun.CanonicalName).RuntimeName -match $regxLUNID
					$lunID      = $Matches.LUNID
					
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
						CanonicalName = $esxScsiLun.CanonicalName
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
