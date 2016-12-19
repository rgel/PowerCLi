Function Write-Menu {

<#
.SYNOPSIS
	Display custom menu in the PowerShell console.
.DESCRIPTION
	The Write-Menu cmdlet creates numbered and colored menues
	in the PS console window and returns the choiced entry.
.PARAMETER Menu
	Menu entries.
.PARAMETER PropertyToShow
	If your menu entries are objects and not the strings
	this is property to show as entry.
.PARAMETER Prompt
	User prompt at the end of the menu.
.PARAMETER Header
	Menu title (optional).
.PARAMETER Shift
	Quantity of <TAB> keys to shift the menu items right.
.PARAMETER TextColor
	Menu text color.
.PARAMETER HeaderColor
	Menu title color.
.PARAMETER AddExit
	Add 'Exit' as very last entry.
.EXAMPLE
	PS C:\> Write-Menu -Menu "Open","Close","Save" -AddExit -Shift 1
	Simple manual menu with 'Exit' entry and 'one-tab' shift.
.EXAMPLE
	PS C:\> Write-Menu -Menu (Get-ChildItem 'C:\Windows\') -Header "`t`t-- File list --`n" -Prompt 'Select any file'
	Folder content dynamic menu with the header and custom prompt.
.EXAMPLE
	PS C:\> Write-Menu -Menu (Get-Service) -Header ":: Services list ::`n" -Prompt 'Select any service' -PropertyToShow DisplayName
	Display local services menu with custom property 'DisplayName'.
.EXAMPLE
	PS C:\> Write-Menu -Menu (Get-Process |select *) -PropertyToShow ProcessName |fl
	Display full info about choicen process.
.INPUTS
	Any type of data (object(s), string(s), number(s), etc).
.OUTPUTS
	[The same type as input object] Single menu item.
.NOTES
	Author      :: Roman Gelman
	Version 1.0 :: 21-Apr-2016 :: [Release]
	Version 1.1 :: 03-Nov-2016 ::  [Change] Now the function supports a single item as menu entry.
.LINK
	http://www.ps1code.com/single-post/2016/04/21/How-to-create-interactive-dynamic-Menu-in-PowerShell
#>

[CmdletBinding()]

Param (

	[Parameter(Mandatory,Position=0)]
		[Alias("MenuEntry","List")]
	$Menu
	,
	[Parameter(Mandatory=$false,Position=1)]
	[string]$PropertyToShow = 'Name'
	,
	[Parameter(Mandatory=$false,Position=2)]
		[ValidateNotNullorEmpty()]
	[string]$Prompt = 'Pick a choice'
	,
	[Parameter(Mandatory=$false,Position=3)]
		[Alias("MenuHeader")]
	[string]$Header = ''
	,
	[Parameter(Mandatory=$false,Position=4)]
		[ValidateRange(0,5)]
		[Alias("Tab","MenuShift")]
	[int]$Shift = 0
	,
	#[Enum]::GetValues([System.ConsoleColor])
	[Parameter(Mandatory=$false,Position=5)]
		[ValidateSet("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta",
		"DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White")]
		[Alias("Color","MenuColor")]
	[string]$TextColor = 'White'
	,
	[Parameter(Mandatory=$false,Position=6)]
		[ValidateSet("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta",
		"DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White")]
	[string]$HeaderColor = 'Yellow'
	,
	[Parameter(Mandatory=$false,Position=7)]
		[ValidateNotNullorEmpty()]
		[Alias("Exit","AllowExit")]
	[switch]$AddExit
)

Begin {

	$ErrorActionPreference = 'Stop'
	If ($Menu -isnot [array]) {$Menu = @($Menu)}
	If ($AddExit) {$MaxLength=8} Else {$MaxLength=9}
	If ($Menu.Length -gt $MaxLength) {$AddZero=$true} Else {$AddZero=$false}
	[hashtable]$htMenu = @{}
}

Process {

	### Write menu header ###
	If ($Header -ne '') {Write-Host $Header -ForegroundColor $HeaderColor}
	
	### Create shift prefix ###
	If ($Shift -gt 0) {$Prefix = [string]"`t"*$Shift}
	
	### Build menu hash table ###
	For ($i=1; $i -le $Menu.Length; $i++) {
		If ($AddZero) {
			If ($AddExit) {$lz = ([string]($Menu.Length+1)).Length - ([string]$i).Length}
			Else          {$lz = ([string]$Menu.Length).Length - ([string]$i).Length}
			$Key = "0"*$lz + "$i"
		} Else {$Key = "$i"}
		$htMenu.Add($Key,$Menu[$i-1])
		If ($Menu[$i] -isnot 'string' -and ($Menu[$i-1].$PropertyToShow)) {
			Write-Host "$Prefix[$Key] $($Menu[$i-1].$PropertyToShow)" -ForegroundColor $TextColor
		} Else {Write-Host "$Prefix[$Key] $($Menu[$i-1])" -ForegroundColor $TextColor}
	}
	If ($AddExit) {
		[string]$Key = $Menu.Length+1
		$htMenu.Add($Key,"Exit")
		Write-Host "$Prefix[$Key] Exit" -ForegroundColor $TextColor
	}
	
	### Pick a choice ###
	Do {
		$Choice = Read-Host -Prompt $Prompt
		If ($AddZero) {
			If ($AddExit) {$lz = ([string]($Menu.Length+1)).Length - $Choice.Length}
			Else          {$lz = ([string]$Menu.Length).Length - $Choice.Length}
			If ($lz -gt 0) {$KeyChoice = "0"*$lz + "$Choice"} Else {$KeyChoice = $Choice}
		} Else {$KeyChoice = $Choice}
	} Until ($htMenu.ContainsKey($KeyChoice))
}

End {return $htMenu.get_Item($KeyChoice)}

} #EndFunction Write-Menu