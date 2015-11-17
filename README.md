# PowerCLi Repo
### Scripts & Modules

### </b><ins>Vi-Module.psm1</ins></b>

To install this module, drop the entire '<b>Vi-Module</b>' folder into one of your module directories.
The default PowerShell module paths are listed in the `$env:PSModulePath` environment variable.
The default per-user module path is: `"$env:HOMEDRIVE$env:HOMEPATH\Documents\WindowsPowerShell\Modules"`.
The default computer-level module path is: `"$env:windir\System32\WindowsPowerShell\v1.0\Modules"`.
To use the module, type following command: `ipmo Vi-Module -Force -Verbose`.
To see the commands imported, type `gc -Module Vi-Module`.
For help on each individual cmdlet or function, run `Get-Help CmdletName -Full [-Online][-Examples]`.

##### <ins>Cmdlets:</ins>

[###### <b>1. Get-RDM</b>] (http://rgel75.wix.com/blog#!How-to-get-RDM-Raw-Device-Mappings-disks-using-PowerCLi/c1tye/5620e39c0cf2c3576e613aa8)
Report all VM with their RDM disks.

###### <b>2. Convert-VmdkThin2EZThick</b>
Inflate thin virtual disks.

###### <b>3. Find-VcVm</b>
Search VC's VM throw direct connection to group of ESXi Hosts.
