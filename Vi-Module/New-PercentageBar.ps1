Function New-PercentageBar {

<#
.SYNOPSIS
	Create percentage bar.
.DESCRIPTION
	This cmdlet creates percentage bar.
.PARAMETER Percent
	Value in percents (%).
.PARAMETER Value
	Value in arbitrary units.
.PARAMETER MaxValue
	100% value.
.PARAMETER BarLength
	Bar length in chars.
.PARAMETER BarView
	Different char sets to build the bar.
.PARAMETER GreenBorder
	Percent value to change bar color from green to yellow (relevant with -DrawBar parameter only).
.PARAMETER YellowBorder
	Percent value to change bar color from yellow to red (relevant with -DrawBar parameter only).
.PARAMETER NoPercent
	Exclude percentage number from the bar.
.PARAMETER DrawBar
	Directly draw the colored bar onto the PowerShell console (unsuitable for calculated properties).
.EXAMPLE
	PS C:\> New-PercentageBar -Percent 90 -DrawBar
	Draw single bar with all default settings.
.EXAMPLE
	PS C:\> New-PercentageBar -Percent 95 -DrawBar -GreenBorder 70 -YellowBorder 90
	Draw the bar and move the both color change borders.
.EXAMPLE
	PS C:\> 85 |New-PercentageBar -DrawBar -NoPercent
	Pipeline the percent value to the function and exclude percent number from the bar.
.EXAMPLE
	PS C:\> For ($i=0; $i -le 100; $i+=10) {New-PercentageBar -Percent $i -DrawBar -Length 100 -BarView AdvancedThin2; "`r"}
	Demonstrates advanced bar view with custom bar length and different percent values.
.EXAMPLE
	PS C:\> $Folder = 'C:\reports\'
	PS C:\> $FolderSize = (Get-ChildItem -Path $Folder |measure -Property Length -Sum).Sum
	PS C:\> Get-ChildItem -Path $Folder -File |sort Length -Descending |select -First 10 |select Name,Length,@{N='SizeBar';E={New-PercentageBar -Value $_.Length -MaxValue $FolderSize}} |ft -au
	Get file size report and add calculated property 'SizeBar' that contains the percent of each file size from the folder size.
.EXAMPLE
	PS C:\> $VolumeC = gwmi Win32_LogicalDisk |? {$_.DeviceID -eq 'c:'}
	PS C:\> Write-Host -NoNewline "Volume C Usage:" -ForegroundColor Yellow; `
	PS C:\> New-PercentageBar -Value ($VolumeC.Size-$VolumeC.Freespace) -MaxValue $VolumeC.Size -DrawBar; "`r"
	Get system volume usage report.
.NOTES
	Author       ::	Roman Gelman.
	Version 1.0  ::	04-Jul-2016  :: Release.
.LINK
	http://www.ps1code.com/single-post/2016/07/16/How-to-create-colored-and-adjustable-Percentage-Bar-in-PowerShell
#>

[CmdletBinding(DefaultParameterSetName='PERCENT')]

Param (
	[Parameter(Mandatory,Position=1,ValueFromPipeline,ParameterSetName='PERCENT')]
		[ValidateRange(0,100)]
	[int]$Percent
	,
	[Parameter(Mandatory,Position=1,ValueFromPipeline,ParameterSetName='VALUE')]
		[ValidateRange(0,[double]::MaxValue)]
	[double]$Value
	,
	[Parameter(Mandatory,Position=2,ParameterSetName='VALUE')]
		[ValidateRange(1,[double]::MaxValue)]
	[double]$MaxValue
	,
	[Parameter(Mandatory=$false,Position=3)]
		[Alias("BarSize","Length")]
		[ValidateRange(10,100)]
	[int]$BarLength = 20
	,
	[Parameter(Mandatory=$false,Position=4)]
		[ValidateSet("SimpleThin","SimpleThick1","SimpleThick2","AdvancedThin1","AdvancedThin2","AdvancedThick")]
	[string]$BarView = "SimpleThin"
	,
	[Parameter(Mandatory=$false,Position=5)]
		[ValidateRange(50,80)]
	[int]$GreenBorder = 60
	,
	[Parameter(Mandatory=$false,Position=6)]
		[ValidateRange(80,90)]
	[int]$YellowBorder = 80
	,
	[Parameter(Mandatory=$false)]
	[switch]$NoPercent
	,
	[Parameter(Mandatory=$false)]
	[switch]$DrawBar
)

Begin {

	If ($PSBoundParameters.ContainsKey('VALUE')) {

		If ($Value -gt $MaxValue) {
			Throw "The [-Value] parameter cannot be greater than [-MaxValue]!"
		}
		Else {
			$Percent = $Value/$MaxValue*100 -as [int]
		}
	}
	
	If ($YellowBorder -le $GreenBorder) {Throw "The [-YellowBorder] value must be greater than [-GreenBorder]!"}
	
	Function Set-BarView ($View) {
		Switch -exact ($View) {
			"SimpleThin"	{$GreenChar = [char]9632; $YellowChar = [char]9632; $RedChar = [char]9632; $EmptyChar = "-"; Break}
			"SimpleThick1"	{$GreenChar = [char]9608; $YellowChar = [char]9608; $RedChar = [char]9608; $EmptyChar = "-"; Break}
			"SimpleThick2"	{$GreenChar = [char]9612; $YellowChar = [char]9612; $RedChar = [char]9612; $EmptyChar = "-"; Break}
			"AdvancedThin1"	{$GreenChar = [char]9632; $YellowChar = [char]9632; $RedChar = [char]9632; $EmptyChar = [char]9476; Break}
			"AdvancedThin2"	{$GreenChar = [char]9642; $YellowChar = [char]9642; $RedChar = [char]9642; $EmptyChar = [char]9643; Break}
			"AdvancedThick"	{$GreenChar = [char]9617; $YellowChar = [char]9618; $RedChar = [char]9619; $EmptyChar = [char]9482; Break}
		}
		$Properties = [ordered]@{
			Char1 = $GreenChar
			Char2 = $YellowChar
			Char3 = $RedChar
			Char4 = $EmptyChar
		}
		$Object = New-Object PSObject -Property $Properties
		$Object
	} #End Function Set-BarView
	
	$BarChars = Set-BarView -View $BarView
	$Bar = $null
	
	Function Draw-Bar {
	
		Param (
			[Parameter(Mandatory)][string]$Char
			,
			[Parameter(Mandatory=$false)][string]$Color = 'White'
			,
			[Parameter(Mandatory=$false)][boolean]$Draw
		)
		
		If ($Draw) {
			Write-Host -NoNewline -ForegroundColor ([System.ConsoleColor]$Color) $Char
		}
		Else {
			return $Char
		}
		
	} #End Function Draw-Bar
	
} #End Begin

Process {
	
	If ($NoPercent) {
		$Bar += Draw-Bar -Char "[ " -Draw $DrawBar
	}
	Else {
		If     ($Percent -eq 100) {$Bar += Draw-Bar -Char "$Percent% [ " -Draw $DrawBar}
		ElseIf ($Percent -ge 10)  {$Bar += Draw-Bar -Char " $Percent% [ " -Draw $DrawBar}
		Else                      {$Bar += Draw-Bar -Char "  $Percent% [ " -Draw $DrawBar}
	}
	
	For ($i=1; $i -le ($BarValue = ([Math]::Round($Percent * $BarLength / 100))); $i++) {
	
		If     ($i -le ($GreenBorder * $BarLength / 100))  {$Bar += Draw-Bar -Char ($BarChars.Char1) -Color 'DarkGreen' -Draw $DrawBar}
		ElseIf ($i -le ($YellowBorder * $BarLength / 100)) {$Bar += Draw-Bar -Char ($BarChars.Char2) -Color 'Yellow' -Draw $DrawBar}
		Else                                               {$Bar += Draw-Bar -Char ($BarChars.Char3) -Color 'Red' -Draw $DrawBar}
	}
	For ($i=1; $i -le ($EmptyValue = $BarLength - $BarValue); $i++) {$Bar += Draw-Bar -Char ($BarChars.Char4) -Draw $DrawBar}
	$Bar += Draw-Bar -Char " ]" -Draw $DrawBar
	
} #End Process

End {
	If (!$DrawBar) {return $Bar}
} #End End

} #EndFunction New-PercentageBar
