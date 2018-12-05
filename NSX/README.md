# ![nsx-256](https://user-images.githubusercontent.com/6964549/49496838-920a3180-f86f-11e8-8c02-c924493b87dc.png)VMware NSX

## [Power-NsxRole.ps1](https://github.com/rgel/PowerCLi/blob/master/NSX/Power-NsxRole.ps1)

### Manage NSX Manager Roles leveraging [PowerNSX](https://github.com/vmware/powernsx) and NSX API

<ins>Requirements:</ins> PowerShell 4 or above. To check, type the following command: `$PSVersionTable.PSVersion.Major`.

To use this script, save the '<b>Power-NsxRole.ps1</b>' file to your computer and go to the script directory, e.g. `cd C:\scripts`.

Import the script to the current PowerShell session: `Import-Module .\Power-NsxRole.ps1 -Force`.

Connect to your NSX Manager(s) by `Connect-NsxServer` cmdlet from the PowerNSX module.

You are ready to invoke imported cmdlets. To see the cmdlets imported, type `Get-Command -Noun nsxentity*`.

All the action cmdlets (`Add-`/`New-`/`Remove-`) are advanced functions and support `-Debug`, `-Verbose` and `-Confirm` parameters.

For help on each individual cmdlet, run `Get-Help CmdletName -Full [-Online][-Examples]`.

|No|Cmdlet|Description|
|----|----|----|
|1|<b>Get-NsxEntityRoleAssignment</b>|Get users and groups who have been assigned a NSX Manager role|
|2|<b>Add-NsxEntityRoleAssignment</b>|Assign the NSX Manager role to any vCenter user or group|
|3|<b>Add-NsxEntityAccessScope</b>|Assign vCenter user or group NSX Manager scope aware role in a custom Access Scope. This replaces `Limit Scope` [capability](https://vswitchzero.com/2018/10/19/limiting-user-scope-and-permissions-in-nsx/), removed from <b>6.2</b> UI and later|
|4|<b>Remove-NsxEntityRoleAssignment</b>|Remove NSX Manager role assignment for any vCenter user or group|
|5|<b>Get-NsxRoleDisplayName</b>|Convert NSX Manager Role name to display name and vice versa (internal helper function)|
