# PowerCLi Repo
### Scripts & Modules

### </b><ins>[Kickstart-VMHostIMM.ps1</ins></b>] (http://goo.gl/XD9RpA)

Kickstart ESXi hosts on IBM/Lenovo servers without PXE using PowerShell.

### </b><ins>Vi-Module.psm1</ins></b>

To install this module, drop the entire '<b>Vi-Module</b>' folder into one of your module directories.
The default PowerShell module paths are listed in the `$env:PSModulePath` environment variable.
The default per-user module path is: `"$env:HOMEDRIVE$env:HOMEPATH\Documents\WindowsPowerShell\Modules"`.
The default computer-level module path is: `"$env:windir\System32\WindowsPowerShell\v1.0\Modules"`.
To use the module, type following command: `ipmo Vi-Module -Force -Verbose`.
To see the commands imported, type `gc -Module Vi-Module`.
For help on each individual cmdlet or function, run `Get-Help CmdletName -Full [-Online][-Examples]`.

##### <ins>Cmdlets:</ins>

###### <b>1. [Get-RDM</b>] (http://goo.gl/3wO4pi)

Report all VM with their RDM disks.

###### <b>2. [Convert-VmdkThin2EZThick</b>] (http://goo.gl/cVpTpO)

Inflate thin virtual disks.

###### <b>3. [Find-VcVm</b>] (http://www.vmgu.ru/news/vmware-vcenter-how-to-find-powered-off)

Search VC's VM throw direct connection to group of ESXi hosts.
