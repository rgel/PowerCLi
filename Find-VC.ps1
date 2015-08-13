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
		[Alias("vCenter")]
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
		$root = $cred.GetNetworkCredential().UserName
		$pwd  = $cred.GetNetworkCredential().Password
		$hosts = @()
		
		For ($i=$PostfixStart; $i -le $PostfixEnd; $i++) {
			If ($AddZero -and $i -match '^\d{1}$') {
				$hosts += $HostSuffix + '0' + $i
			} Else {
				$hosts += $HostSuffix + $i
			}
		}
		Connect-VIServer $hosts -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -User $root -Password $pwd |select Name,IsConnected |ft -AutoSize
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
