<#
.SYNOPSIS
	Create input file for IBM's multiple warranties lookup.
.DESCRIPTION
	This script create input file for upload to the IBM's multiple warranties lookup service.
.PARAMETER Report
	Report file's full path.
.PARAMETER OpenBrowser
	Open IBM 'Warranty and parts lookup' site in your default browser.
.PARAMETER ShowReport
	View report file.
.PARAMETER MaxCommentLength
	Comments value maximum length in symbols.
.EXAMPLE
	PS C:\> cd C:\scripts
	PS C:\scripts> .\Get-IBMVMHostWarranty.ps1
	Create report file in the script directory.
.EXAMPLE
	PS C:\scripts> .\Get-IBMVMHostWarranty.ps1 -Report 'C:\reports\IBM_Warranty.txt'
.EXAMPLE
	PS C:\scripts> .\Get-IBMVMHostWarranty.ps1 'C:\reports\IBM_Warranty.txt'
.EXAMPLE
	PS C:\scripts> Get-Item 'C:\reports\IBM_Warranty.txt' |.\Get-IBMVMHostWarranty.ps1
.EXAMPLE
	PS C:\scripts> .\Get-IBMVMHostWarranty.ps1 'C:\reports\IBM_Warranty.txt' -OpenBrowser
.EXAMPLE
	PS C:\scripts> .\Get-IBMVMHostWarranty.ps1 -Report 'C:\reports\IBM_Warranty.txt' -OpenBrowser -ShowReport
.INPUTS
	[System.IO.DirectoryInfo] [System.String] File path.
.OUTPUTS
	[System.String[]].
.NOTES
	Author: Roman Gelman.
.LINK
	https://goo.gl/Yg7mYp
#>

Param (

	[Parameter(Mandatory=$false,Position=1,ValueFromPipeline=$true,HelpMessage="Report file's full path")]
		[ValidateScript({Test-Path (Split-Path $_) -PathType Container})]
	[System.IO.DirectoryInfo] [System.String]$Report = ("$PSScriptRoot\IBM_Warranty.txt")
	,
	[Parameter(Mandatory=$false,Position=2,HelpMessage="Open IBM Warranty and parts lookup site")]
	[Switch]$OpenBrowser
	,
	[Parameter(Mandatory=$false,Position=3,HelpMessage="Open report file")]
	[Switch]$ShowReport
	,
	[Parameter(Mandatory=$false,Position=4,HelpMessage="Comments maximum length")]
		[ValidateRange(3,50)]
	[System.UInt16]$MaxCommentLength = 50
)

Begin {

	If ($Report.GetType().BaseType.Name -eq 'FileSystemInfo') {$ReportPath = $Report.ToString()} Else {$ReportPath = $Report}
	$maxBytes = 4096

}

Process {

	Try
		{

			Get-VMHost |? {'Connected','Maintenance' -contains $_.ConnectionState -and $_.Version -ge 5} |sort Name |% {
				
				$hdwInfo = ($_ |Get-EsxCli).hardware.platform.get()
				
				If ($hdwInfo.VendorName -eq 'IBM') {	#If ('IBM','Lenovo' -contains $hdwInfo.VendorName) {
				
						$Model  = [Regex]::Match($hdwInfo.ProductName, '\[(\d{4}).*?\]').Groups[1].Value
						$Serial = $hdwInfo.SerialNumber
						$VMHost = [Regex]::Match($_.Name, '^(.+?)(\.|$)').Groups[1].Value
						If ($VMHost.Length -gt $MaxCommentLength) {$VMHost = $VMHost.Substring(0, $MaxCommentLength)}
						"$Model,$Serial,$VMHost" |Out-File -FilePath $ReportPath -Encoding UTF8 -Append -Confirm:$false -Force
				}
			}
		}
	Catch
		{
			"{0}" -f $Error.Exception.Message
			Exit 1
		}
		
		$GrowProc = [Math]::Round((Get-Item $ReportPath).Length*100/$maxBytes, 0)
		If ($GrowProc -le 80) {$Color = 'Green'} ElseIf (81..100 -contains $GrowProc) {$Color = 'Yellow'} Else {$Color = 'Red'}
		Write-Host "`nThe report file size is $GrowProc`% from allowed maximum [$maxBytes Bytes]`n" -ForegroundColor $Color
}

End {

	If ($OpenBrowser) {
		$link = 'https://www-947.ibm.com/support/entry/portal/wlup'
		New-PSDrive -Name HKCR -PSProvider registry -Root Hkey_Classes_Root | Out-Null
		$browserPath = ((Get-ItemProperty 'HKCR:\http\shell\open\command').'(default)').Split('"')[1]
		& $browserPath $link
		Write-Host "Click on the " -NoNewline
		Write-Host "'Loookup multiple warranties using input file'" -ForegroundColor Yellow -NoNewline
		Write-Host " link`nand than click on the " -NoNewline
		Write-Host "'Browse...' " -ForegroundColor Yellow -NoNewline
		Write-Host "button`nto upload the " -NoNewline
		Write-Host "'$ReportPath' " -ForegroundColor Yellow -NoNewline
		Write-Host "report file.`n"
		Start-Sleep 3
	}
	
	If ($ShowReport) {Invoke-Item $ReportPath}

}
