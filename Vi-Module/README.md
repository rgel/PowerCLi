# ![powercli](https://user-images.githubusercontent.com/6964549/49510073-dc030f80-f88f-11e8-9f9a-e1f0415c7ad2.png)$${\color{green}VMware \space VI \space Automation \space Module}$$

> [!NOTE]
> PowerShell `5` or above is required\
> To check, type the following: `$PSVersionTable.PSVersion.Major`

To install this module, drop the entire `Vi-Module` folder into one of your module directories

The default PowerShell module paths are listed in the `$env:PSModulePath` environment variable

To make it look better, split the paths in this manner: `$env:PSModulePath -split ';'`

The default per-user module path is: `"$env:HOMEDRIVE$env:HOMEPATH\Documents\WindowsPowerShell\Modules"`

The default computer-level module path is: `"$env:windir\System32\WindowsPowerShell\v1.0\Modules"`

To use the module, type following command: `Import-Module Vi-Module -Force -Verbose`

To see the commands imported, type `Get-Command -Module Vi-Module`

For help on each individual cmdlet or function, run `Get-Help CmdletName -Full [-Online][-Examples]`

|No|Cmdlet|Description|
|----|----|----|
|1|[<b>Get-RDM</b>](https://ps1code.com/2015/10/16/get-rdm-disks-powercli)|Get all VM with their RDM (Raw Device Mappings) disks|
|2|[<b>Convert-VmdkThin2EZThick</b>](https://ps1code.com/2015/11/05/convert-vmdk-thin2thick-powercli)|Inflate thin virtual disks|
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
|13|[<b>Connect-VMHostPutty</b>](https://ps1code.com/2016/12/27/esxi-powershell-and-putty)|Connect to ESXi host(s) by putty SSH client with no password!|
|14|[<b>Set-MaxSnapshotNumber</b>](https://ps1code.com/2017/01/24/max-snap-powercli)|Set maximum allowed VM snapshot number|
|15|[<b>Get-VMHostGPU</b>](https://ps1code.com/2017/04/23/esxi-vgpu-powercli)|Get ESXi host(s) GPU info|
|16|[<b>Test-VMHotfix</b>](https://ps1code.com/2017/05/23/test-vm-hotfix)|Test VM for installed Hotfix(es)|
|17|[<b>Test-VMPing</b>](https://ps1code.com/2017/05/23/test-vm-hotfix)|Test VM accessibility|
|18|[<b>Search-Datastore</b>](https://ps1code.com/2016/08/21/search-datastores-powercli)|Browse/Search VMware Datastores|
|19|[<b>Get-VMHostPnic/Get-VMHostHba</b>](https://ps1code.com/2017/06/18/esxi-peripheral-devices-powercli)|Get ESXi hosts Peripheral devices|
|20|[<b>Set-SdrsCluster/Get-SdrsCluster</b>](https://ps1code.com/2017/08/16/sdrs-powercli-part1)|Configure Storage DRS clusters|
|21|[<b>Add-SdrsAntiAffinityRule/Get-SdrsAntiAffinityRule/Remove-SdrsAntiAffinityRule</b>](https://ps1code.com/2017/09/06/sdrs-powercli-part2)|Create and delete SDRS Anti-Affinity Rules|
|22|[<b>Invoke-SdrsRecommendation</b>](https://ps1code.com/2017/09/06/sdrs-powercli-part2)|Run Storage DRS recommendations|
|23|[<b>Set-SdrsAntiAffinityRule</b>](https://ps1code.com/2017/09/10/sdrs-powercli-part3)|Configure SDRS Anti-Affinity Rules|
|24|[<b>Convert-VI2PSCredential</b>](https://ps1code.com/2017/09/18/vi2ps-cred-powercli)|Securely save and retrieve credentials|
|25|[<b>Get-VMGuestPartition/Expand-VMGuestPartition</b>](https://ps1code.com/2017/10/17/extend-vm-guest-part-powercli)|Extend VM Guest Partition|
|26|[<b>Get-ViSession/Disconnect-ViSession</b>](https://ps1code.com/2017/11/21/vcenter-sessions-powercli)|List and disconnect VCenter sessions|
|27|[<b>New-SmartSnapshot</b>](https://ps1code.com/2017/11/26/vmware-smart-snapshot-powercli)|Intellectual VMware snapshots|
|28|[<b>Get-VMHostCDP</b>](https://ps1code.com/2018/03/25/cdp-powercli)|Leverage Cisco Discovery Protocol|
|29|[<b>Get-VMLoggedOnUser</b>](https://ps1code.com/2018/11/22/vm-logged-on-powercli)|Get VM Logged On users|
