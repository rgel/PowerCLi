# ![powerclilogo](https://cloud.githubusercontent.com/assets/6964549/17082247/44e1392e-517f-11e6-9cbe-9efa0277deaa.png)
## VMware PowerCLi Scripts & Modules

### [<ins>Copy-VMNotes2CompDescr.ps1</ins>](https://github.com/rgel/PowerCLi/blob/master/Copy-VMNotes2CompDescr.ps1)

###### <b>How to copy VMware VM Notes to Computer/AD Computer Account Description</b>

### [<ins>Kickstart-VMHostIMM.ps1</ins>](https://github.com/rgel/PowerCLi/tree/master/Kickstart)

###### <b>Kickstart ESXi hosts on IBM/Lenovo servers without PXE using PowerShell</b>

### [<ins>Get-IBMVMHostWarranty.ps1</ins>](https://github.com/rgel/PowerCLi/blob/master/Get-IBMVMHostWarranty.ps1)

###### <b>Create enterprise-wide input file for IBM multiple warranty lookup using PowerShell</b>

### [<ins>Vi-Module</ins>](https://github.com/rgel/PowerCLi/tree/master/Vi-Module)

To install this module, drop the entire '<b>Vi-Module</b>' folder into one of your module directories.

The default PowerShell module paths are listed in the `$env:PSModulePath` environment variable.

To make it look better, split the paths in this manner: `$env:PSModulePath -split ';'`

The default per-user module path is: `"$env:HOMEDRIVE$env:HOMEPATH\Documents\WindowsPowerShell\Modules"`.

The default computer-level module path is: `"$env:windir\System32\WindowsPowerShell\v1.0\Modules"`.

To use the module, type following command: `Import-Module Vi-Module -Force -Verbose`.

To see the commands imported, type `Get-Command -Module Vi-Module`.

For help on each individual cmdlet or function, run `Get-Help CmdletName -Full [-Online][-Examples]`.

#### <b><ins>Vi-Module cmdlets:</ins></b>

|No|Cmdlet|Description|
|----|----|----|
|1|[<b>Get-RDM</b>](https://ps1code.com/category/vmware-powercli/vi-module/)|Report all VM with their RDM disks|
|2|[<b>Convert-VmdkThin2EZThick</b>](https://ps1code.com/category/vmware-powercli/vi-module/)|Inflate thin virtual disks|
|3|[<b>Find-VcVm</b>](https://cloud.githubusercontent.com/assets/6964549/17361776/d5dff80e-597a-11e6-85a2-a782db875f78.png)|Search VCenter VM throw direct connection to group of ESXi hosts. Thanks to <i>VMGU.ru</i> for the [article](http://www.vmgu.ru/news/vmware-vcenter-how-to-find-powered-off)|
|4|[<b>Set-PowerCLiTitle</b>](https://ps1code.com/2015/11/17/set-powercli-title)|Write connected VI servers info to PowerCLi window title bar|
|5|[<b>Get-VMHostFirmwareVersion</b>](https://ps1code.com/2016/01/09/esxi-bios-firmware-version-powercli)|Get a Firmware version and release date of your ESXi hosts|
|6|[<b>Compare-VMHostSoftwareVib</b>](https://ps1code.com/2016/09/26/compare-esxi-powercli)|Deprecated. Use `Compare-VMHost -Compare VIB` instead|
|7|[<b>Get-VMHostBirthday</b>](https://cloud.githubusercontent.com/assets/6964549/12399803/c8439dfa-be24-11e5-8141-09199caa301e.png)|Get ESXi hosts' installation date. Thanks to <i>Magnus Andersson</i> for his [idea](http://vcdx56.com/2016/01/05/find-esxi-installation-date/)|
|8|[<b>Enable-VMHostSSH/Disable-VMHostSSH</b>](https://ps1code.com/2016/02/07/enable-disable-ssh-esxi-powercli)|Enable/Disable SSH on all ESXi hosts in a cluster|
|9|[<b>Set-VMHostNtpServer</b>](https://ps1code.com/2016/03/10/set-esxi-ntp-powercli)|Set `NTP Servers` setting on ESXi hosts|
|10|[<b>Get-Version</b>](https://ps1code.com/2016/05/25/get-version-powercli)|Get VMware Virtual Infrastructure objects' version info: `VM`, `ESXi Hosts`, `VDSwitches`, `Datastores`, `VCenters`, `PowerCLi`, `License Keys`|
|11|[<b>Compare-VMHost</b>](https://ps1code.com/2016/09/26/compare-esxi-powercli)|Compare two or more ESXi hosts with PowerCLi|
|12|[<b>Move-Template2Datastore</b>](https://ps1code.com/2016/12/19/migrate-vm-template-powercli)|Invoke Storage VMotion task for VM Template(s)|
|13|[<b>Connect-VMHostPutty</b>](https://ps1code.com/category/vmware-powercli/vi-module/)|Connect to ESXi host(s) by putty SSH client with no password!|
|14|[<b>Set-MaxSnapshotNumber</b>](https://ps1code.com/2017/01/24/max-snap-powercli)|Set maximum allowed VM snapshot number|
|15|[<b>Get-VMHostGPU</b>](https://ps1code.com/2017/04/23/esxi-vgpu-powercli)|Get ESXi host(s) GPU info|
|16|[<b>Test-VMHotfix</b>](https://ps1code.com/2017/05/23/test-vm-hotfix)|Test VM for installed Hotfix(es)|
|17|[<b>Test-VMPing</b>](https://ps1code.com/2017/05/23/test-vm-hotfix)|Test VM accessibility|

### [<ins>VSAN</ins>](https://github.com/rgel/PowerCLi/tree/master/VSAN)

#### <b><ins>VSAN Module cmdlets:</ins></b>

|No|Cmdlet|Description|
|----|----|----|
|1|[<b>Get-VSANHealthCheckSupported</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Get all available VSAN Health Checks. [Idea](http://www.virtuallyghetto.com/2017/04/managing-silencing-vsan-health-checks-using-powercli.html#more-22754) by William Lam|
|2|[<b>Get-VSANHealthCheckSkipped</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Get skipped VSAN Health Checks. [Idea](http://www.virtuallyghetto.com/2017/04/managing-silencing-vsan-health-checks-using-powercli.html#more-22754) by William Lam|
|3|[<b>Get-VSANHealthCheckGroup</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Get all VSAN Health Check groups. [Idea](http://www.virtuallyghetto.com/2017/04/managing-silencing-vsan-health-checks-using-powercli.html#more-22754) by William Lam|
|4|[<b>Enable-VSANHealthCheckSkipped</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Enable skipped VSAN Health Check(s). [Idea](http://www.virtuallyghetto.com/2017/04/managing-silencing-vsan-health-checks-using-powercli.html#more-22754) by William Lam|
|5|[<b>Disable-VSANHealthCheck</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Disable VSAN Health Check(s). [Idea](http://www.virtuallyghetto.com/2017/04/managing-silencing-vsan-health-checks-using-powercli.html#more-22754) by William Lam|
|6|[<b>Get-VSANSmartData</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Get SMART drive data. [Idea](http://www.virtuallyghetto.com/2017/04/smart-drive-data-now-available-using-vsan-management-6-6-api.html) by William Lam|
|7|[<b>Get-VSANVersion</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Get VSAN health service version. [Idea](http://www.virtuallyghetto.com/2017/04/getting-started-wthe-new-powercli-6-5-1-get-vsanview-cmdlet.html) by William Lam|
|8|[<b>Get-VSANHealthSummary</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Fetch VSAN Cluster Health status|
|9|[<b>Invoke-VSANHealthCheck</b>](https://ps1code.com/2017/05/08/vsan-health-check)|Run VSAN Cluster Health Test|

### [<ins>VAMI</ins>](https://github.com/rgel/PowerCLi/tree/master/VAMI)

#### <b><ins>VAMI (Virtual Appliance Management Interface) Module cmdlets:</ins></b>

|No|Cmdlet|Description|
|----|----|----|
|1|[<b>Get-VAMIHealth</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get Appliance health summary|
|2|[<b>Get-VAMISummary</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get basic Appliance info|
|3|[<b>Get-VAMIAccess</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get access interfaces|
|4|[<b>Get-VAMIBackupSize</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get estimated backup size|
|5|[<b>Get-VAMIDisks</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get VMDK disk number to OS partition mapping|
|6|[<b>Get-VAMIStorageUsed/Start-VAMIDiskResize</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get OS partition usage & Resize partition|
|7|[<b>Get-VAMINetwork</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get networking info|
|8|[<b>Get-VAMIPerformance</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get CPU% & Memory% usage|
|9|[<b>Get-VAMIService/Restart-VAMIService/Start-VAMIService/Stop-VAMIService</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get & control services' state|
|10|[<b>Get-VAMIStatsList</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get available monitoring metrics|
|11|[<b>Get-VAMITime</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Get current Time and NTP info|
|12|[<b>Get-VAMIUser/New-VAMIUser/Remove-VAMIUser</b>](https://ps1code.com/2017/05/11/vami-powercli-module)|Manipulate local users|

