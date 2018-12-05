#requires -Version 4.0 -Modules 'PowerNSX'

Function Get-NsxRoleDisplayName
{
	
<#
.SYNOPSIS
	Convert NSX Manager Role name to display name and vice versa.
.DESCRIPTION
	This small helper function converts NSX API security Role name to
	the vSphere client Role Display name and vice versa.
.PARAMETER NsxRole
	Specifies NSX role name or display name.
.PARAMETER Reverse
	If specified, the parameter -NsxRole interpreted as Display name.
.EXAMPLE
	PS C:\> 'super_user' | Get-NsxRoleDisplayName
.EXAMPLE
	PS C:\> 'Enterprise Administrator' | Get-NsxRoleDisplayName -Reverse
.EXAMPLE
	PS C:\> Get-NsxRoleDisplayName 'NSX Administrator' -Reverse
.EXAMPLE
	PS C:\> Get-NsxRoleDisplayName -NsxRole 'security_admin'
.NOTES
	Author      :: Roman Gelman @rgelman75
	Version 1.0 :: 02-Dec-2018 :: [Release] :: Publicly available
	Version 1.1 :: 03-Dec-2018 :: [Change] :: Two new roles are introduced in NSX 6.4.2 (Security & Network Engineer)
.LINK
	https://ps1code.com/
#>
	
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[string]$NsxRole
		 ,
		[switch]$Reverse
	)
	
	Begin
	{
		$NsxRoles = @{
			'super_user' = 'System Administrator';
			'vshield_admin' = 'NSX Administrator';
			'enterprise_admin' = 'Enterprise Administrator';
			'security_admin' = 'Security Administrator';
			'auditor' = 'Auditor';
			'security_engineer' = 'Security Engineer';
			'network_engineer' = 'Network Engineer'
		}
	}
	Process
	{
		if ($Reverse) { ($NsxRoles.GetEnumerator() | ? { $_.Value -eq $NsxRole }).Name }
		else { if ($NsxRoles.ContainsKey($NsxRole)) { $NsxRoles.$NsxRole } else { "$NsxRole" } }
	}
	
} #EndFunction Get-NsxRoleDisplayName
	
Function Add-NsxEntityAccessScope
{
	
<#
.SYNOPSIS
	Assign vCenter user or group NSX Manager scope aware role in a custom Access Scope.
.DESCRIPTION
	This function adds user or group to a NSX Manager and assigns
	scope aware role in a custom Access Scope.
.PARAMETER AccessScope
	Specifies NSX Edge(s), DLR(s) or Logical Switch(es).
.PARAMETER User
	Specifies vCenter user's UPN (ex: user@vsphere.local or user@domain.com).
.PARAMETER Group
	Specifies vCenter group name (ex: group@vsphere.local or group@domain.com).
.PARAMETER Role
	Specifies scope aware NSX role.
.EXAMPLE
	PS C:\> Get-NsxEdge esg_Lab1 | Add-NsxEntityAccessScope -User NSXAdmin1@vsphere.local -Role Auditor -Debug
.EXAMPLE
	PS C:\> Get-NsxLogicalSwitch -TransportZone trz_Lab | Add-NsxEntityAccessScope NSXAdmin1@domain.com -Verbose -Confirm:$false
.EXAMPLE
	PS C:\> Get-NsxLogicalRouter dlr_Lab1 | Add-NsxEntityAccessScope -Group NSXAdmins@vsphere.local
.EXAMPLE
	PS C:\> $scope = @(Get-NsxEdge esg_Lab1)
	PS C:\> $scope += Get-NsxLogicalRouter dlr_Lab1
	PS C:\> $scope += Get-NsxTransportZone trz_Lab | Get-NsxLogicalSwitch
	PS C:\> Add-NsxEntityAccessScope NSXAdmin1@vsphere.local -AccessScope $scope
	Compose a scope from multiple objects of different types (Edge, DLR and Logical switches).
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5 | PowerNSX 3.0.1081
	Platform    :: Tested on vSphere 6.5 : VCSA 6.5 & NSX 6.4
	Dependency  :: PowerNSX Module
	Version 1.0 :: 04-Dec-2018 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess, DefaultParameterSetName = 'USR')]
	[Alias('New-NsxEntityAccessScope')]
	[OutputType([pscustomobject])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		$AccessScope
		 ,
		[Parameter(Mandatory, Position = 1, ParameterSetName = 'USR')]
		[ValidatePattern("^.+@.+$")]
		[string[]]$User
		 ,
		[Parameter(Mandatory, ParameterSetName = 'GRP')]
		[ValidatePattern("^.+@.+$")]
		[string[]]$Group
		 ,
		[Parameter()]
		[ValidateSet('Auditor', 'Security Administrator',
					 'Security Engineer', 'Network Engineer')]
		[string]$Role = 'Security Administrator'
	)
	
	Begin
	{
		$NsxRole = Get-NsxRoleDisplayName $Role -Reverse
		$StartXml = "<accessControlEntry>`n<role>$NsxRole</role>"
		$Scope = @()
		$EndXml = "`n</accessControlEntry>"
		
		$Entity = @{}
		if ($PSCmdlet.ParameterSetName -eq 'USR')
		{
			$Entity.Add('Name', $User)
			$Entity.Add('Type', 'user')
			$Entity.Add('IsGroup', 'false')
		}
		else
		{
			$Entity.Add('Name', $Group)
			$Entity.Add('Type', 'group')
			$Entity.Add('IsGroup', 'true')
		}
		
		$EdgeName = @()
	}
	Process
	{
		$Scope += foreach ($NsxObject in $AccessScope)
		{
			if ($NsxObject -is [System.Xml.XmlElement])
			{
				if (($NsxObject | Get-Member -MemberType Property, NoteProperty).Name -contains 'objectTypeName')
				{	
					$ObjId = 'objectid'
					$ObjType = ($NsxObject.objectTypeName).Replace('VirtualWire', 'Logical Switch')
				}
				else
				{
					$ObjId = 'id'
					$ObjType = 'NSX Edge'
				}
				"`n<resource><resourceId>$($NsxObject.$ObjId)</resourceId></resource>"
				$EdgeName += $NsxObject.name
				Write-Verbose "The $ObjType [$($NsxObject.$ObjId)] will be added to the scope"
			}
			else
			{
				Write-Verbose "The [$NsxObject] is not PowerNSX object"	
			}
		}
	}
	End
	{
		$PostBody = $StartXml + $Scope + $EndXml
		
		foreach ($NsxServer in $DefaultNSXConnection)
		{
			if ((Invoke-NsxRestMethod -connection $NsxServer -method get -URI "/api/2.0/services/usermgmt/roles").list.string -contains $NsxRole)
			{
				foreach ($ACE in $Entity.Name)
				{
					Try
					{
						$XmlAce = (Invoke-NsxRestMethod -connection $NsxServer -method get -URI "/api/2.0/services/usermgmt/role/$ACE" -ea Stop).accessControlEntry
						$ResourceScope = if ($XmlAce.resource.name) { $XmlAce.resource.name -join ', ' } else { 'Global' }
						Write-Output "The $($Entity.Type) [$ACE] in NSX Manager [$($NsxServer.Server)] already has [$($XmlAce.role | Get-NsxRoleDisplayName)] role in the [$ResourceScope] scope"
					}
					Catch
					{
						if ($PSCmdlet.ShouldProcess("NSX Manager [$($NsxServer.Server)]", "Assign [$Role] role within Access Scope [$($EdgeName -join ', ')] to the $($Entity.Type) [$ACE]"))
						{
							$Uri = "/api/2.0/services/usermgmt/role/$($ACE)??isGroup=$($Entity.IsGroup)"
							Invoke-NsxRestMethod -connection $NsxServer -method post -URI $Uri -body $PostBody
							Write-Debug "`nUri: $Uri`nBody:`n$($PostBody | Format-XML)"
							
							[pscustomobject] @{
								NsxManager = $NsxServer.Server
								Entity = $ACE
								Type = (Get-Culture).TextInfo.ToTitleCase($Entity.Type)
								Role = $Role
								Scope = $($EdgeName -join ', ')
							}
						}
					}
				}
			}
			else
			{
				Write-Verbose "The NSX Manager [$($NsxServer.Server)] version $($NsxServer.Version) does not support [$Role] role"
			}
		}
	}
	
} #EndFunction Add-NsxEntityAccessScope

Function Remove-NsxEntityRoleAssignment
{
	
<#
.SYNOPSIS
	Remove NSX Manager role assignment for any vCenter user or group.
.DESCRIPTION
	This function removes NSX Manager role assignment for any vCenter user(s) or group(s).
.PARAMETER User
	Specifies vCenter user's UPN (ex: user@vsphere.local or user@domain.com).
.PARAMETER Group
	Specifies vCenter group name (ex: group@vsphere.local or group@domain.com).
.EXAMPLE
	PS C:\> Remove-NsxEntityRoleAssignment -User NSXAdmin1@vsphere.local
.EXAMPLE
	PS C:\> Remove-NsxEntityRoleAssignment -Group NSXAdmins@vsphere.local
.EXAMPLE
	PS C:\> Remove-NsxEntityRoleAssignment NSXAdmin1@vsphere.local, NSXAdmin2@vsphere.local -Verbose
.EXAMPLE
	PS C:\> Remove-NsxEntityRoleAssignment -Group NSXAdmins@vsphere.local, NSXAdmins@domain.com -Confirm:$false
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5 | PowerNSX 3.0.1081
	Platform    :: Tested on vSphere 6.5 : VCSA 6.5 & NSX 6.4
	Dependency  :: PowerNSX Module
	Version 1.0 :: 03-Dec-2018 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess, DefaultParameterSetName = 'USR')]
	[OutputType([pscustomobject])]
	Param (
		[Parameter(Mandatory, Position = 1, ParameterSetName = 'USR')]
		[ValidatePattern("^.+@.+$")]
		[string[]]$User
		 ,
		[Parameter(Mandatory, ParameterSetName = 'GRP')]
		[ValidatePattern("^.+@.+$")]
		[string[]]$Group
	)
	
	Begin
	{
		$Entity = @{ }
		if ($PSCmdlet.ParameterSetName -eq 'USR')
		{
			$Entity.Add('Name', $User)
			$Entity.Add('Type', 'user')
			$Entity.Add('IsGroup', 'false')
		}
		else
		{
			$Entity.Add('Name', $Group)
			$Entity.Add('Type', 'group')
			$Entity.Add('IsGroup', 'true')
		}
	}
	Process
	{
		foreach ($NsxServer in $DefaultNSXConnection)
		{
			foreach ($ACE in $Entity.Name)
			{
				Try
				{
					$XmlAce = (Invoke-NsxRestMethod -connection $NsxServer -method get -URI "/api/2.0/services/usermgmt/role/$ACE").accessControlEntry
					$ResourceScope = if ($XmlAce.resource) { $XmlAce.resource.name -join ', ' } else { 'Global' }
					if ($PSCmdlet.ShouldProcess("NSX Manager [$($NsxServer.Server)] - scope [$ResourceScope]", "Remove [$($XmlAce.role | Get-NsxRoleDisplayName)] role assignment for the entity [$ACE]"))
					{
						Invoke-NsxRestMethod -connection $NsxServer -method 'del' -URI "/api/2.0/services/usermgmt/role/$($ACE)??isGroup=$($Entity.IsGroup)"
						
						[pscustomobject] @{
							NsxManager = $NsxServer.Server
							Entity = $ACE
							Type = (Get-Culture).TextInfo.ToTitleCase($Entity.Type)
							Role = $XmlAce.role | Get-NsxRoleDisplayName
							Scope = $ResourceScope
						}
					}
				}
				Catch
				{
					Write-Verbose "The $($Entity.Type) [$ACE] from NSX Manager [$($NsxServer.Server)] skipped because no role assigned"
				}
			}
		}
	}
	End { }
	
} #EndFunction Remove-NsxEntityRoleAssignment

Function Add-NsxEntityRoleAssignment
{
	
<#
.SYNOPSIS
	Assign the NSX Manager role to any vCenter user or group.
.DESCRIPTION
	This function assigns NSX Manager role to any vCenter user(s) or group(s).
.PARAMETER User
	Specifies vCenter user's UPN (ex: user@vsphere.local or user@domain.com).
.PARAMETER Group
	Specifies vCenter group name (ex: group@vsphere.local or group@domain.com).
.PARAMETER Role
	Specifies NSX role.
.EXAMPLE
	PS C:\> Add-NsxEntityRoleAssignment -User NSXAdmin1@vsphere.local
.EXAMPLE
	PS C:\> Add-NsxEntityRoleAssignment -Group NSXAdmins@vsphere.local
.EXAMPLE
	PS C:\> Add-NsxEntityRoleAssignment NSXAdmin1@vsphere.local, NSXAdmin2@vsphere.local -Verbose
.EXAMPLE
	PS C:\> Add-NsxEntityRoleAssignment -Group NSXAdmins@vsphere.local, NSXAdmins@domain.com -Confirm:$false
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5 | PowerNSX 3.0.1081
	Platform    :: Tested on vSphere 6.5 : VCSA 6.5 & NSX 6.4
	Dependency  :: PowerNSX Module
	Version 1.0 :: 03-Dec-2018 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess, DefaultParameterSetName = 'USR')]
	[Alias('New-NsxEntityRoleAssignment')]
	[OutputType([pscustomobject])]
	Param (
		[Parameter(Mandatory, Position = 1, ParameterSetName = 'USR')]
		[ValidatePattern("^.+@.+$")]
		[string[]]$User
		 ,
		[Parameter(Mandatory, ParameterSetName = 'GRP')]
		[ValidatePattern("^.+@.+$")]
		[string[]]$Group
		 ,
		[Parameter()]
		[ValidateSet('Auditor', 'Security Administrator',
			   'Enterprise Administrator', 'NSX Administrator', 'System Administrator',
			   'Security Engineer', 'Network Engineer')]
		[string]$Role = 'Enterprise Administrator'
	)
	
	Begin
	{
		$NsxRole = Get-NsxRoleDisplayName $Role -Reverse
		$StartXml = "<accessControlEntry>"
		$RoleXml = "`n<role>$NsxRole</role>"
		$RoleXml += if ('Auditor', 'Security Administrator', 'Security Engineer', 'Network Engineer' -contains $Role) { "`n<resource><resourceId>globalroot-0</resourceId></resource>" }
		$EndXml = "`n</accessControlEntry>"
		
		$Entity = @{ }
		if ($PSCmdlet.ParameterSetName -eq 'USR')
		{
			$Entity.Add('Name', $User)
			$Entity.Add('Type', 'user')
			$Entity.Add('IsGroup', 'false')
		}
		else
		{
			$Entity.Add('Name', $Group)
			$Entity.Add('Type', 'group')
			$Entity.Add('IsGroup', 'true')
		}
	}
	Process
	{
		foreach ($NsxServer in $DefaultNSXConnection)
		{
			if ((Invoke-NsxRestMethod -connection $NsxServer -method get -URI "/api/2.0/services/usermgmt/roles").list.string -contains $NsxRole)
			{	
				foreach ($ACE in $Entity.Name)
				{
					Try
					{
						$XmlAce = (Invoke-NsxRestMethod -connection $NsxServer -method get -URI "/api/2.0/services/usermgmt/role/$ACE").accessControlEntry
						Write-Debug "`n$($XmlAce | Format-XML)"
						$ResourceScope = if ($XmlAce.resource) { $XmlAce.resource.name -join ', ' } else { 'Global' }
						Write-Output "The $($Entity.Type) [$($Entity.Name)] in NSX Manager [$($NsxServer.Server)] already has [$($XmlAce.role | Get-NsxRoleDisplayName)] role in the [$ResourceScope] scope"
					}
					Catch
					{
						if ($PSCmdlet.ShouldProcess("NSX Manager [$($NsxServer.Server)]", "Assign [$Role] role to the entity [$ACE]"))
						{
							$Uri = "/api/2.0/services/usermgmt/role/$($ACE)??isGroup=$($Entity.IsGroup)"
							$PostBody = $StartXml + $RoleXml + $EndXml
							Write-Debug "`nUri: $Uri`nBody:`n$($PostBody | Format-XML)"
							Invoke-NsxRestMethod -connection $NsxServer -method post -URI $Uri -body $PostBody
							
							[pscustomobject] @{
								NsxManager = $NsxServer.Server
								Entity = $ACE
								Type = (Get-Culture).TextInfo.ToTitleCase($Entity.Type)
								Role = $Role
								Scope = 'Global'
							}
						}
					}
				}
			}
			else
			{
				Write-Verbose "The NSX Manager [$($NsxServer.Server)] version $($NsxServer.Version) does not support [$Role] role"
			}
		}
	}
	End { }
	
} #EndFunction Add-NsxEntityRoleAssignment

Function Get-NsxEntityRoleAssignment
{
	
<#
.SYNOPSIS
	Get users and groups who have been assigned a NSX Manager role.
.DESCRIPTION
	This function retrieves information about local as well as vCenter
	users and groups who have been assigned a NSX Manager role.
.PARAMETER Entity
	Specifies user or group pattern.
.PARAMETER AccessScope
	If specified, only users and groups with Access Scope defined returned.
.PARAMETER Role
	Specifies NSX role.
.EXAMPLE
	PS C:\> Get-NsxEntityRoleAssignment | Format-Table -AutoSize
.EXAMPLE
	PS C:\> Get-NsxEntityRoleAssignment -Entity '\admin'
	Search for user/group by name.
.EXAMPLE
	PS C:\> Get-NsxEntityRoleAssignment nsx -Role 'Security Administrator'
	Search for user/group by name and role.
.EXAMPLE
	PS C:\> Get-NsxEntityRoleAssignment -AccessScope
	Accounts with Access Scope defined.
.EXAMPLE
	PS C:\> Get-NsxEntityRoleAssignment | Where-Object {$_.Domain -ne 'cli' -and !$_.Enabled}
	Make custom search for disabled domain accounts.
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5 | PowerNSX 3.0.1081
	Platform    :: Tested on vSphere 6.5 : VCSA 6.5 & NSX 6.4
	Dependency  :: PowerNSX Module
	Version 1.0 :: 04-Dec-2018 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/
#>
	
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	Param (
		[Parameter(Position = 0)]
		[ValidateNotNullOrEmpty()]
		[string]$Entity
		 ,
		[Parameter()]
		[ValidateSet('Auditor', 'Security Administrator',
					 'Enterprise Administrator', 'NSX Administrator', 'System Administrator',
					 'Security Engineer', 'Network Engineer')]
		[string]$Role
		 ,
		[Parameter()]
		[switch]$AccessScope
	)
	
	Begin { $GlobalScope = 'Global' }
	Process
	{
		foreach ($NsxServer in $DefaultNSXConnection)
		{
			$XmlAce = (Invoke-NsxRestMethod -connection $NsxServer -method get -URI "/api/2.0/services/usermgmt/users/vsm").users.userInfo
			
			$RoleAssigned += $XmlAce | % {
				
				$Type = if ($_.isGroup -eq 'false') { 'User' } else { 'Group' }
				$Enabled = if ($_.isEnabled -eq 'true') { $true } else { $false }
				$IsCli = if ($_.isCli -eq 'true') { $true } else { $false }
				$IsUni = if ($_.isUniversal -eq 'true') { $true } else { $false }
				$Scope = if ($_.hasGlobalObjectAccess -eq 'true') { $GlobalScope } else { ($_.accessControlEntry.resource.name | Sort-Object) -join ', ' }
				$Domain = if ($_.name -match '\\') { ([regex]::Match($_.name, '^(.+)\\')).Groups[1] } else { 'CLI' }
				
				[pscustomobject] @{
					NsxManager = $NsxServer.Server
					Domain = "$Domain".ToUpper()
					Entity = $_.name
					Type = $Type
					Enabled = $Enabled
					Universal = $IsUni
					Role = Get-NsxRoleDisplayName $_.accessControlEntry.role
					Scope = $Scope
				}
			}
			### Filter by Entity name ###
			$RoleAssigned = if ($PSBoundParameters.ContainsKey('Entity')) { ($RoleAssigned).Where{ $_.Entity -imatch $([regex]::Escape($Entity)) } } else { $RoleAssigned }
			### Filter by Role assigned ###	
			$RoleAssigned = if ($PSBoundParameters.ContainsKey('Role')) { ($RoleAssigned).Where{ $_.Role -eq $Role } } else { $RoleAssigned }
			### Return only roles with Access Scope defined ###	
			$RoleAssigned = if ($AccessScope) { ($RoleAssigned).Where{ $_.Scope -ne $GlobalScope } } else { $RoleAssigned }
		}
	}
	End { return $RoleAssigned | Sort-Object 'Type', Entity }
	
} #EndFunction Get-NsxEntityRoleAssignment
