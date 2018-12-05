#requires -Version 3.0
#requires -Modules 'ActiveDirectory'

<#
.SYNOPSIS
	Copy VMware VM Notes to Computer/AD Computer Account description.
.DESCRIPTION
	This script copy VM 'Notes' value to Computer description & Active Directory Computer Account description
	and add custom string and Cluster name to it. Example: "VM Notes | VMware :: Cluster"
.PARAMETER Cluster
	Specifies target Cluster object(s) to get VM Notes from it.
.PARAMETER CustomString
	Specifies custom string followed after the Notes.
.PARAMETER HelperCsv
	Specifies intermediate export/import CSV file to preserve NON english chars.
	By default created in the script directory.
.PARAMETER TargetEnv
	Specifies target environment (Local|Active Directory).
.EXAMPLE
	PS C:\> cd C:\scriptpath
	PS C:\scriptpath> .\Copy-VMNotes2ComputerDescription.ps1 -Cluster (Get-Cluster prod)
.EXAMPLE
	PS C:\scriptpath> Get-Cluster prod |.\Copy-VMNotes2ComputerDescription.ps1 AD -CustomString ' '
.EXAMPLE	
	PS C:\scriptpath> $res = Get-Cluster prod, test |.\Copy-VMNotes2ComputerDescription.ps1 -HelperCsv 'C:\reports\VMNotes.csv' -TargetEnv Local
.EXAMPLE
	PS C:\scriptpath> Get-Cluster prod, test |.\Copy-VMNotes2ComputerDescription.ps1 -ErrorOnly |ft VM, ComputerName, Error -au
	Get failed computers only.
.EXAMPLE
	PS C:\scriptpath> Get-Cluster test |.\Copy-VMNotes2ComputerDescription.ps1
.EXAMPLE
	PS C:\scriptpath> Get-Cluster |.\Copy-VMNotes2ComputerDescription.ps1 -Verbose |epcsv -notype -Encoding utf8 .\Result.csv
.NOTES
	Author      :: Roman Gelman @rgelman75
	Requirement :: PowerShell 3.0
	Dependency  :: ActiveDirectory PowerShell Module (part of R.S.A.T.)
	Version 1.0 :: 14-Dec-2015 :: [Release]
	Version 2.0 :: 18-Jun-2017 :: [Change] :: Full rework
.LINK
	https://ps1code.com/2015/12/14/copy-vmware-vm-notes-2-comp-descr
#>

[CmdletBinding()]
[OutputType([PSCustomObject])]
Param (
	[Parameter(Mandatory, ValueFromPipeline)]
	[VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster
	 ,
	[Parameter(Mandatory = $false)]
	[Alias("AddString")]
	[string]$CustomString = ' | VMware :: '
	 ,
	[Parameter(Mandatory = $false)]
	[ValidateScript({Test-Path ($_ |Split-Path) -PathType 'Container'})]
	[string]$HelperCsv = "$PSScriptRoot\VMNotes.csv"
	 ,
	[Parameter(Mandatory = $false, Position = 0)]
	[ValidateSet("ALL", "AD", "Local")]
	[Alias("Environment")]
	[string]$TargetEnv = 'ALL'
	 ,
	[Parameter(Mandatory = $false)]
	[switch]$ErrorOnly
)

Begin
{
	$rgxErrorMsg = '^(?<Error>.+?)(\.|$)'
	$rgxTruncate = '^(.+?)(\.|$)'
	$WarningPreference = 'SilentlyContinue'
	$ErrorActionPreference = 'Stop'
	$ScriptName = '{0}' -f $MyInvocation.MyCommand
	Write-Verbose "$ScriptName started at [$(Get-Date)]"
}
Process
{
	$StatErrLocal = 0
	$StatErrAD = 0
	
	### Export/Import Cluster ###
	Write-Progress -Activity "Export VM Notes" -Status "Cluster [$($Cluster.Name)]" -CurrentOperation "Exporting to [$HelperCsv] ..."
	$Cluster | Get-VM -vb:$false | select Name, Notes,
		@{ N = 'GuestFamily'; E = { $_.ExtensionData.Guest.GuestFamily } },
		@{ N = 'GuestHostname'; E = { $_.Guest.HostName } } |
		? { $_.Notes -and $_.GuestFamily -eq 'windowsGuest' } |
		select * -exclude GuestFamily | sort Name | epcsv -NoTypeInformation -Encoding utf8 $HelperCsv
	$import = ipcsv -Encoding utf8 $HelperCsv
	Write-Progress -Completed $true -Status "Please wait"
	
	### Copy to AD ###
	if ('ALL', 'AD' -contains $TargetEnv)
	{
		for ($i = 0; $i -lt $import.Length; $i++)
		{
			$VMGuestFqdn = if ('localhost', $null -notcontains $import[$i].GuestHostname) { $import[$i].GuestHostname } else { $import[$i].Name }
			$VMGuestHostname = [regex]::Match($VMGuestFqdn, $rgxTruncate).Groups[1].Value
			
			Try
			{
				Set-ADComputer -Identity $VMGuestHostname -Description "$($import[$i].Notes)$CustomString$($Cluster.Name)" -Confirm:$false
				Write-Progress -Activity "Set AD Computer Account Description" `
							   -Status "Cluster [$($Cluster.Name)]" `
							   -CurrentOperation "Current CN [$VMGuestHostname]" `
							   -PercentComplete ($i/$import.Length*100)
				$ErrorMsg = ''
			}
			Catch
			{
				$ErrorMsg = [regex]::Match(("{0}" -f $Error.Exception.Message), $rgxErrorMsg).Groups[2].Value
				$StatErrAD += 1
			}
			Finally
			{
				$return = [pscustomobject] @{
					VM = $import[$i].Name
					ComputerName = $VMGuestHostname
					Cluster = $Cluster.Name
					Env = 'AD'
					VMNotes = $import[$i].Notes
					Error = $ErrorMsg
				}
				if ($ErrorOnly) { if ($return.Error) { $return } } else { $return }
			}
		}
		Write-Progress -Completed $true -Status "Please wait"
	}
	
	### Copy to Local ###
	if ('ALL', 'Local' -contains $TargetEnv)
	{
		for ($i = 0; $i -lt $import.Length; $i++)
		{
			$VMGuestHostname = if ('localhost', $null -notcontains $import[$i].GuestHostname) { $import[$i].GuestHostname } else { $import[$i].Name }
			
			Try
			{
				$CN = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $VMGuestHostname
				$CN.Description = "$($import[$i].Notes)$CustomString$($Cluster.Name)"
				$null = $CN.Put()
				Write-Progress -Activity "Set Remote Computer Description" `
							   -Status "Cluster [$($Cluster.Name)]" `
							   -CurrentOperation "Current Computer [$VMGuestHostname]" `
							   -PercentComplete ($i/$import.Length*100)
				$ErrorMsg = ''
			}
			Catch
			{
				$ErrorMsg = [regex]::Match(("{0}" -f $Error.Exception.Message), $rgxErrorMsg).Groups[2].Value
				$StatErrLocal += 1
			}
			Finally
			{
				$return = [pscustomobject] @{
					VM = $import[$i].Name
					ComputerName = $VMGuestHostname
					Cluster = $Cluster.Name
					Env = 'Local'
					VMNotes = $import[$i].Notes
					Error = $ErrorMsg
				}
				if ($ErrorOnly) { if ($return.Error) { $return } } else { $return }
			}
		}
	}
	Write-Verbose "$ScriptName statistic: Cluster: [$($Cluster.Name)]; Total VM: [$($import.Count)]; Failed AD: [$StatErrAD]; Failed Local: [$StatErrLocal]"
}
End
{
	Write-Verbose "$ScriptName finished at [$(Get-Date)]"
}
