# ![vsan-256](https://user-images.githubusercontent.com/6964549/49511294-6e58e280-f893-11e8-8f41-f024dd5e9d63.png)$${\color{green}VMware \space VSAN \space Management \space Module}$$

> [!NOTE]
> PowerShell `3` or above is required\
> To check, type the following: `$PSVersionTable.PSVersion.Major`

To install this module, drop the entire '<b>VSAN</b>' folder into one of your module directories

The default PowerShell module paths are listed in the `$env:PSModulePath` environment variable

To make it look better, split the paths in this manner: `$env:PSModulePath -split ';'`

The default per-user module path is: `"$env:HOMEDRIVE$env:HOMEPATH\Documents\WindowsPowerShell\Modules"`

The default computer-level module path is: `"$env:windir\System32\WindowsPowerShell\v1.0\Modules"`

To use the module, type following command: `Import-Module VSAN -Force -Verbose`

To see the commands imported, type `Get-Command -Module VSAN`

For help on each individual cmdlet or function, run `Get-Help CmdletName -Full [-Online][-Examples]`

|No|Cmdlet|Description|
|----|----|----|
|1|[<b>Get-VSANHealthCheckSupported</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Get all available VSAN Health Checks. [Idea](http://www.virtuallyghetto.com/2017/04/managing-silencing-vsan-health-checks-using-powercli.html#more-22754) by William Lam|
|2|[<b>Get-VSANHealthCheckSkipped</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Get skipped VSAN Health Checks. [Idea](http://www.virtuallyghetto.com/2017/04/managing-silencing-vsan-health-checks-using-powercli.html#more-22754) by William Lam|
|3|[<b>Get-VSANHealthCheckGroup</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Get all VSAN Health Check groups. [Idea](http://www.virtuallyghetto.com/2017/04/managing-silencing-vsan-health-checks-using-powercli.html#more-22754) by William Lam|
|4|[<b>Enable-VSANHealthCheckSkipped</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Enable skipped VSAN Health Check(s). [Idea](http://www.virtuallyghetto.com/2017/04/managing-silencing-vsan-health-checks-using-powercli.html#more-22754) by William Lam|
|5|[<b>Disable-VSANHealthCheck</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Disable VSAN Health Check(s). [Idea](http://www.virtuallyghetto.com/2017/04/managing-silencing-vsan-health-checks-using-powercli.html#more-22754) by William Lam|
|6|[<b>Get-VSANSmartData</b>](https://ps1code.com/2017/05/08/vsan-health-check)|<b>`Update!`</b>Get S.M.A.R.T drive data. [Idea](http://www.virtuallyghetto.com/2017/04/smart-drive-data-now-available-using-vsan-management-6-6-api.html) by William Lam|
|7|[<b>Get-VSANVersion</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Get VSAN health service version. [Idea](http://www.virtuallyghetto.com/2017/04/getting-started-wthe-new-powercli-6-5-1-get-vsanview-cmdlet.html) by William Lam|
|8|[<b>Get-VSANHealthSummary</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Fetch VSAN Cluster Health status|
|9|[<b>Invoke-VSANHealthCheck</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Run VSAN Cluster Health Test|
|10|[<b>Get-VSANCapability</b>](https://ps1code.com/2017/07/19/vsan-capabilities)|Get VSAN capabilities|
|11|<b>Get-VSANUsage</b>|Get VSAN Datastore usage. [Idea](https://www.virtuallyghetto.com/2018/06/retrieving-detailed-per-vm-space-utilization-on-vsan.html) by William Lam|
|12|<b>Get-VSANLimit</b>|Get VSAN Cluster limits. [Idea](http://www.virtuallyghetto.com/2017/06/how-to-convert-vsan-rvc-commands-into-powercli-andor-other-vsphere-sdks.html) by William Lam|
