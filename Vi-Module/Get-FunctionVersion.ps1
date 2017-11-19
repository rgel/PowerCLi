Function Get-FunctionVersion
{
	
<#
.SYNOPSIS
	Get PowerShell function version.
.DESCRIPTION
	This function retrieves PowerShell function's current version or version history.
.PARAMETER Function
	Specifies PowerShell function(s)/filter(s), returned by Get-Command cmdlet.
.PARAMETER History
	If specified, a whole function version history returned.
.EXAMPLE
	PS C:\> Get-Command Get-RDM |Get-FunctionVersion -History
	Get version history for a single function.
.EXAMPLE
	PS C:\> Get-Command Get-RDM, Get-Version |Get-FunctionVersion
.EXAMPLE
	PS C:\> Get-Command -Module Vi-Module |sort Name |Get-FunctionVersion |select * -exclude descr* |ft -au
	Get current version of all functions in a module.
.EXAMPLE
	PS C:\> Get-Command -Module Vi-Module |Get-FunctionVersion -h |sort Function, Version |Format-Table -AutoSize
.NOTES
	Author      :: Roman Gelman @rgelman75
	Version 1.0 :: 16-Aug-2017 :: [Release] :: Publicly available
	Version 1.1 :: 19-Nov-2017 :: [Bugfix] :: Regex edited to prevent false positives while using a variable or cmdlet, containing 'Version' word in the function's code
.LINK
	https://ps1code.com
#>
	
	[CmdletBinding()]
	[Alias("fv")]
	[OutputType([PSCustomObject])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		$Function
		 ,
		[Parameter(Mandatory = $false)]
		[switch]$History
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$WarningPreference = 'SilentlyContinue'
		$rgxVersion = 'Version\s+.+\:{2}'
		$rgxVersionInfo = 'Version\s(?<Version>[\d|\.]+)\s+:{2}\s(?<Date>.+)\s:{2}\s(?<Info>.+)\s+:{2}\s(?<Descr>.*$)'
		$Now = [datetime]::Now
	}
	Process
	{
		if ($Function -is [System.Management.Automation.FunctionInfo] -or $Function -is [System.Management.Automation.FilterInfo])
		{
			$VersionInfo = $Function.Definition.Split([System.Environment]::NewLine) | Select-String $rgxVersion
			$Versions = if ($PSBoundParameters.ContainsKey('History')) { $VersionInfo } else { $VersionInfo | select -Last 1 }
			
			foreach ($VersionLine in $Versions)
			{
				$VersionGroups = [regex]::Match($VersionLine.Line, $rgxVersionInfo)
				$Version = Try { [version]$VersionGroups.Groups['Version'].Value } Catch { [version]::New() }
				$Date = Try { [datetime]$VersionGroups.Groups['Date'].Value } Catch { [datetime]'30-Oct-1975' }
				
				[pscustomobject] @{
					Function = $Function.Name
					FunctionType = $Function.CommandType
					Version = $Version
					Published = $Date.Tostring('dd/MM/yyyy')
					DaysAgo = (New-TimeSpan -Start $Date -End $Now).Days
					Type = $VersionGroups.Groups['Info'].Value -replace ('\[', $null) -replace ('\]', $null)
					Description = $VersionGroups.Groups['Descr'].Value
					Module = $Function.ModuleName
					ModuleVersion = $Function.Version
				}
			}
		}
	}
	End
	{
		
	}
	
} #EndFunction Get-FunctionVersion
