# ![vami-256](https://user-images.githubusercontent.com/6964549/49511546-1ff81380-f894-11e8-9625-c6c4ce4e854d.png)VMware VAMI Automation Module

<ins>Requirements:</ins> PowerShell 3 or above. To check, type the following command: `$PSVersionTable.PSVersion.Major`.

To install this module, drop the entire '<b>VAMI</b>' folder into one of your module directories.

The default PowerShell module paths are listed in the `$env:PSModulePath` environment variable.

To make it look better, split the paths in this manner: `$env:PSModulePath -split ';'`

The default per-user module path is: `"$env:HOMEDRIVE$env:HOMEPATH\Documents\WindowsPowerShell\Modules"`.

The default computer-level module path is: `"$env:windir\System32\WindowsPowerShell\v1.0\Modules"`.

To use the module, type following command: `Import-Module VAMI -Force -Verbose`.

To see the commands imported, type `Get-Command -Module VAMI`.

For help on each individual cmdlet or function, run `Get-Help CmdletName -Full [-Online][-Examples]`.

|No|Cmdlet|Description|
|----|----|----|
|1|[<b>Get-VAMIHealth</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get Appliance health summary|
|2|[<b>Get-VAMISummary</b>](https://ps1code.com/2017/12/10/vcsa-backup-expiration-powercli)|<b>`Update!`</b>Get basic Appliance info|
|3|[<b>Get-VAMIAccess/Set-VAMIAccess</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get & <b>`New!`</b>enable/disable access interfaces (SSH, Shell, Console & DCUI)|
|4|[<b>Get-VAMIBackupSize</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get estimated backup size|
|5|[<b>Get-VAMIDisks</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get VMDK disk number to OS partition mapping|
|6|[<b>Get-VAMIStorageUsed/Start-VAMIDiskResize</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get OS partition usage & Resize partition|
|7|[<b>Get-VAMINetwork</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get networking info|
|8|[<b>Get-VAMIPerformance</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get CPU% & Memory% usage|
|9|[<b>Get-VAMIService/Restart-VAMIService/Start-VAMIService/Stop-VAMIService</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get & control services' state|
|10|[<b>Get-VAMIStatsList</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get available monitoring metrics|
|11|[<b>Get-VAMITime</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get current Time and NTP info|
|12|[<b>Get-VAMIUser/New-VAMIUser/Remove-VAMIUser</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Manipulate local users|
|13|<b>Stop-VAMIAppliance</b>|<b>`New!`</b>Shutdown/Reboot VMware Appliance|
|14|<b>Suspend-VAMIShutdown</b>|<b>`New!`</b>Cancel pending VMware Appliance reboot/shutdown|
