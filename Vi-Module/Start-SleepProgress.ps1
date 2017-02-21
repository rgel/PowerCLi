Function Start-SleepProgress {

<#
.SYNOPSIS
	Put a script in the sleep with progress bar.
.DESCRIPTION
	The Start-SleepProgress cmdlet puts a script or cmdlet in the sleep for specified interval
	of either seconds/minutes/hours or until specified timestamp.
.PARAMETER Second
	Seconds to sleep.
.PARAMETER Minute
	Minutes to sleep.
.PARAMETER Hour
	Hours to sleep.
.PARAMETER Until
	Sleep until this date/time.
.PARAMETER Force
	If desired timestamp specified by -Until parameter
	earlier than current time, then assume it will be tomorrow.
.PARAMETER ScriptBlock
	Execute this code after the sleep is finished.
	Must be enclosed in the curly braces {}.
.EXAMPLE
	C:\PS> Start-SleepProgress -Second 20
.EXAMPLE
	C:\PS> Start-SleepProgress 10
	The default are seconds.
.EXAMPLE
	C:\PS> Start-SleepProgress -Minutes 1.5
	Sleep ninety seconds.
.EXAMPLE
	C:\PS> Start-SleepProgress -Hour 1.25
	Sleep one hour and fifteen minutes.
.EXAMPLE
	C:\PS> Start-SleepProgress -Until (Get-Date -Hour 0 -Minute 0 -Second 0).AddDays(1) -ScriptBlock {(Get-Service).Where{$_.Status -eq 'Running'} > '.\services.txt'}
	Take snapshot of all running services and export the list to a text file at midnight.
.EXAMPLE
	C:\PS> For ($i=0; $i -lt 10; $i++) {Start-SleepProgress -s 5 -ScriptBlock {(dir "$env:windir\Temp\" |sort LastWriteTime -Descending).Where({$_.Name -like '*.tmp'},'First')}}
	Every five seconds get the newest ".TMP" file from Windows temp directory. Do it ten times.
.EXAMPLE
	C:\PS> Start-SleepProgress -Until 08:45
	Sleep until today 8:45 AM.
.EXAMPLE
	C:\PS> Start-SleepProgress -Until 08:45 -Force
	Sleep until 8:45 AM. Maybe either today or tomorrow, it depends on the current time.
.EXAMPLE
	C:\PS> Start-SleepProgress -Until 1:45PM
	Sleep until 13:45.
.EXAMPLE
	C:\PS> Start-SleepProgress -Until (Get-Date -Hour 2 -Minute 0 -Second 0).AddDays(1)
	Sleep until tomorrow 2:00 AM.
.NOTES
	Author       ::	Roman Gelman
	Version 1.0  ::	20-Nov-2016 :: [Release]
	The Start-SleepProgress cmdlet requires PowerShell 3.0
	Some examples that use the .Where() method require PowerShell 4.0 or later.
	The maximum sleep interval is twenty-four hours.
.LINK
	http://www.ps1code.com/single-post/2016/11/20/Put-PowerShell-scripts-in-the-sleep-with-progress-bar
#>

[CmdletBinding(DefaultParameterSetName='SEC')]

Param(

  	[Parameter(Mandatory,Position=0,ParameterSetName='SEC')]
		[ValidateRange(1,86400)]
		[Alias("Seconds","s")]
	[uint32]$Second
	,
	[Parameter(Mandatory,ParameterSetName='MIN')]
		[ValidateRange(1,1440)]
		[Alias("Minutes","m")]
	[decimal]$Minute
	,
	[Parameter(Mandatory,ParameterSetName='HOUR')]
		[ValidateRange(1,24)]
		[Alias("Hours","h")]
	[decimal]$Hour
	,
	[Parameter(Mandatory,ParameterSetName='TIME')]
	[datetime]$Until
	,
	[Parameter(Mandatory=$false,ParameterSetName='TIME')]
	[switch]$Force
	,
	[Parameter(Mandatory=$false)]
		[Alias("RunAfter")]
	[scriptblock]$ScriptBlock
)

Begin {

	Switch -exact ($PSCmdlet.ParameterSetName) {
		
		'SEC' {
			$TimeSpan = New-TimeSpan -Start (Get-Date) -End (Get-Date).AddSeconds($Second)
			Break
		}
		'MIN' {
			$Second   = $Minute * 60 -as [uint32]
			$TimeSpan = New-TimeSpan -Start (Get-Date) -End (Get-Date).AddSeconds($Second)
			Break
		}
		'HOUR' {
			$Second   = $Hour * 3600 -as [uint32]
			$TimeSpan = New-TimeSpan -Start (Get-Date) -End (Get-Date).AddSeconds($Second)
			Break
		}
		'TIME' {
			$TimeSpan = New-TimeSpan -Start ([datetime]::Now) -End $Until
			$TotalSecond = $TimeSpan.TotalSeconds
			If ($TotalSecond -le 0) {
				If ($Force) {Start-SleepProgress -Until $Until.AddDays(1)}
				Else {Throw "The timestamp [ $($Until.ToString()) ] is in the past!`nUse [-Force] parameter to shift the timestamp to tomorrow [ $($Until.AddDays(1)) ]."}
			} Else {
				$Second = $TotalSecond -as [uint32]
			}
		}
		
	} #EndSwitch
	
	$h = 'hour'
	$m = 'minute'
	$s = 'second'
	
	If ($TimeSpan.Hours -ne 1)   {$h=$h+'s'}
	If ($TimeSpan.Minutes -ne 1) {$m=$m+'s'}
	If ($TimeSpan.Seconds -ne 1) {$s=$s+'s'}
	
	Function Add-LeadingZero {
		Param ([Parameter(Mandatory,Position=0)][int]$Digit)
		$str = $Digit.ToString()
		If ($str.Length -eq 1) {$str = '0'+$str}
		return $str
	} #EndFunction Add-LeadingZero

} #EndBegin

Process {

	If ($PSCmdlet.ParameterSetName -eq 'SEC') {
	
		For ($i=1; $i -le $Second; $i++) {

		  	Write-Progress -Activity "Waiting $($TimeSpan.Hours) $h $($TimeSpan.Minutes) $m and $($TimeSpan.Seconds) $s ..." `
			-CurrentOperation "Left time: $([int]($Second - $i)) seconds" `
			-Status "Elapsed time: $i seconds" -PercentComplete (100/$Second*$i)
		    Start-Sleep -Milliseconds 980
		}
	} Else {
	
		For ($i=1; $i -le $Second; $i++) {

			$Now         = Get-Date
			$TimeElapsed = New-TimeSpan -Start $Now -End $Now.AddSeconds($i)
			$TimeLeft    = New-TimeSpan -Start $Now -End $Now.AddSeconds([int]($Second-$i))
		  	Write-Progress -Activity "Waiting $($TimeSpan.Hours) $h $($TimeSpan.Minutes) $m and $($TimeSpan.Seconds) $s ..." `
			-CurrentOperation "Left time: $(Add-LeadingZero $TimeLeft.Hours):$(Add-LeadingZero $TimeLeft.Minutes):$(Add-LeadingZero $TimeLeft.Seconds)" `
			-Status "Elapsed time: $(Add-LeadingZero $TimeElapsed.Hours):$(Add-LeadingZero $TimeElapsed.Minutes):$(Add-LeadingZero $TimeElapsed.Seconds)" `
			-PercentComplete (100/$Second*$i)
		    Start-Sleep -Milliseconds 980
		}
	}
	
	Write-Progress -Activity "Completed" -Completed
	
} #EndProcess

End {
	If ($PSBoundParameters.ContainsKey('ScriptBlock')) {&$ScriptBlock}
} #End

} #EndFunction Start-SleepProgress
