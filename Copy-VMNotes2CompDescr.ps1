#requires -Version 3.0
#requires -Modules 'ActiveDirectory'

<#
.SYNOPSIS
	Copy VMware VM Notes to Computer/AD Computer Account description.
.DESCRIPTION
	This script copy VM 'Notes' value to Computer description & Active Directory Computer Account description
	and add custom string and Cluster name to it. Example: "VM Notes | VMware :: Cluster"
.PARAMETER Cluster
	Target HA/DRS Cluster to get VM Notes from it.
.PARAMETER CustomString
	Custom string followed after the Notes.
.PARAMETER HelperCsv
	Intermediate export/import CSV file to preserve NON english chars.
	By default created in the script directory.
.PARAMETER TargetEnv
	Target environment (Local|Active Directory).
.EXAMPLE
	PS C:\> cd C:\scriptpath
	PS C:\scriptpath> .\Copy-VMNotes2CompDescr.ps1 -Cluster (Get-Cluster prod)
.EXAMPLE
	PS C:\scriptpath> Get-Cluster |.\Copy-VMNotes2CompDescr.ps1
.EXAMPLE
	PS C:\scriptpath> Get-Cluster prod |.\Copy-VMNotes2CompDescr.ps1 -TargetEnv AD -CustomString ' '
.EXAMPLE	
	PS C:\scriptpath> $res = Get-Cluster prod,test |.\Copy-VMNotes2CompDescr.ps1 -HelperCsv 'C:\reports\VMNotes.csv' -TargetEnv Local
.EXAMPLE
	PS C:\scriptpath> $res = Get-Cluster prod,test |.\Copy-VMNotes2CompDescr.ps1
	PS C:\scriptpath>$res |? {$_.Notes} |ft -au
	Get failed computers only.
.INPUTS
	[VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl[]] Cluster objects returned by Get-Cluster cmdlet.
.OUTPUTS
	[System.Management.Automation.PSCustomObject] PSObject collection.
.NOTES
	Dependencies:
	[1] ActiveDirectory module.
	C:\PS> Get-Module -ListAvailable |? {$_.Name -eq 'ActiveDirectory'}
	[2] VM Name = OS hostname.
	Script assumes that VM Name in VCenter/ESXi is equal to the hostname within VM Operating System.
	Author: Roman Gelman.
.LINK
	http://rgel75.wix.com/blog
#>

Param (

	[Parameter(Mandatory,Position=1,ValueFromPipeline,ValueFromPipelineByPropertyName,HelpMessage="Get-Cluster")]
	[VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl[]]$Cluster
	,
	[Parameter(Mandatory=$false,Position=2,HelpMessage="Custom string followed after the Notes")]
		[Alias("AddString")]
	[System.String]$CustomString = ' | VMware :: '
	,
	[Parameter(Mandatory=$false,Position=3,HelpMessage="Intermediate CSV file")]
		[ValidateScript({Test-Path ($_ |Split-Path) -PathType 'Container'})]
	[System.String]$HelperCsv = ("$PSScriptRoot\VMNotes.csv")
	,
	[Parameter(Mandatory=$false,Position=4,HelpMessage="Target environment (Local|Active Directory)")]
		[ValidateSet("ALL","AD","Local")]
		[Alias("Target","Environment")]
	[System.String]$TargetEnv = 'ALL'
)

Begin {
	$rgxNBHname  = ',|~|:|!|@|\#|\$|%|\^|&|`|\(|\)|\{|\}|_|\s|\\|/|\*|\?|"|<|>|\|'
	$rgxErrorMsg = '^(?<Error>.+?)(\.|$)'
}

Process {

Foreach ($cluObj in $Cluster) {

	$clu = $cluObj.Name
	
	$cluObj |Get-VM |select Name,Notes `
	,@{N='GuestFamily';E={$_.ExtensionData.Guest.GuestFamily}} `
	|? {$_.Name -notmatch $rgxNBHname -and $_.Notes.Length -gt 0 -and $_.GuestFamily -eq 'windowsGuest'} `
	|select Name,Notes |sort Name |epcsv -NoTypeInformation -Encoding utf8 $HelperCsv

	$import = ipcsv -Encoding utf8 $HelperCsv
	
	If ('ALL','AD' -contains $TargetEnv) {
	
		For ($i=0; $i -lt $import.Length; $i++) {
			Try {
					Set-ADComputer -Identity "$($import[$i].Name)" -Description "$($import[$i].Notes)$CustomString$clu" -Confirm:$false -ErrorAction:Stop
					Write-Progress -Activity "Set AD Computer Account Description" -Status "Cluster : $clu" -CurrentOperation "Current CN : $($import[$i].Name)" -PercentComplete ($i/$import.Length*100)
					$Properties = [ordered]@{
						ComputerName = $import[$i].Name
						Cluster      = $clu
						Env          = 'AD'
						Notes        = ''
					}
				}
			Catch
				{
					$Properties = [ordered]@{
						ComputerName = $import[$i].Name
						Cluster      = $clu
						Env          = 'AD'
						Notes        = [Regex]::Match(("{0}" -f $Error.Exception.Message), $rgxErrorMsg).Groups[2].Value
					}
				}
			Finally
				{
					$Object = New-Object PSObject -Property $Properties
					$Object
				}
		}
		Write-Progress -Completed $true -Status "Please wait"
		
	}
	
	If ('ALL','Local' -contains $TargetEnv) {
	
		For ($i=0; $i -lt $import.Length; $i++) {
			Try {
					$CN = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $import[$i].Name -ErrorAction:Stop
					$CN.Description = "$($import[$i].Notes)$CustomString$clu"
					$null = $CN.Put()
					Write-Progress -Activity "Set Remote Computer Description" -Status "Cluster : $clu" -CurrentOperation "Current Computer : $($import[$i].Name)" -PercentComplete ($i/$import.Length*100)
					$Properties = [ordered]@{
						ComputerName = $import[$i].Name
						Cluster      = $clu
						Env          = 'Local'
						Notes        = ''
					}
					
				}
			Catch
				{
					$Properties = [ordered]@{
						ComputerName = $import[$i].Name
						Cluster      = $clu
						Env          = 'Local'
						Notes        = [Regex]::Match(("{0}" -f $Error.Exception.Message), $rgxErrorMsg).Groups[2].Value
					}
				}
			Finally
				{
					$Object = New-Object PSObject -Property $Properties
					$Object
				}
		}
		
	}
}

}

End {

}
