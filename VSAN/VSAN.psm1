Function Get-VSANVersion
{
	
<#
.SYNOPSIS
	Get vSAN health service version.
.DESCRIPTION
    This function retreives vSAN health service version at the vCenter Server level as well as for the individual ESXi host(s).
.PARAMETER VsanCluster
    Specifies a vSAN Cluster object(s), returned by Get-Cluster cmdlet.
.EXAMPLE
    PS C:\> Get-Cluster |Get-VSANVersion -Verbose
.EXAMPLE
    PS C:\> Get-Cluster VSAN-Cluster |Get-VSANVersion |sort Version
.NOTES
	Idea        :: William Lam @lamw
	Author      :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5.1, VSAN 6.6
	Version 1.0 :: 26-Apr-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/04/getting-started-wthe-new-powercli-6-5-1-get-vsanview-cmdlet.html
#>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Alias("Cluster")]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$VsanCluster
	)
	
	Begin
	{
		$vchs = Get-VsanView -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system" -Verbose:$false
	}
	Process
	{
		if ($VsanCluster.VsanEnabled)
		{
			$result = $vchs.VsanVcClusterQueryVerifyHealthSystemVersions($VsanCluster.Id)
			$return = $result.HostResults | select Hostname, Version | sort Hostname
			$VcName = if ($global:DefaultVIServers.Length -eq 1) {$global:DefaultVIServer.Name} else {'VC'}
			$vc = [pscustomobject] @{ Hostname = $VcName; Version = $result.VcVersion }
			$return
			$vc
		}
		else
		{
			Write-Verbose "The [$($VsanCluster.Name)] cluster is not VSAN Enabled"
		}
	}
	End { }
	
} #EndFunction Get-VSANVersion

Function Get-VSANHealthCheckGroup
{
	
<#
.SYNOPSIS
	Get all vSAN Health Check groups.
.DESCRIPTION
    This function retreives the list of vSAN Health Check groups (categories).
.EXAMPLE
    PS C:\> Get-VSANHealthCheckGroup
.NOTES
	Idea        :: William Lam @lamw
	Author      :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5.1, VSAN 6.6
	Version 1.0 :: 26-Apr-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/04/managing-silencing-vsan-health-checks-using-powercli.html#more-22754
#>
	
	$vchs = Get-VsanView -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system"
	$vchs.VsanQueryAllSupportedHealthChecks() | sort -Property GroupName | select group* -Unique
	
} #EndFunction Get-VSANHealthCheckGroup

Function Get-VSANHealthCheckSupported
{
	
<#
.SYNOPSIS
	Get all available vSAN Health Checks.
.DESCRIPTION
    This function retreives all available vSAN Health Checks.
.PARAMETER TestGroupId
    Specifies the Id of a vSAN Health Check group.
.EXAMPLE
	PS C:\> Get-VSANHealthCheckSupported
.EXAMPLE
    PS C:\> Get-VSANHealthCheckSupported -TestGroupId perfsvc
.EXAMPLE
    PS C:\> Get-VSANHealthCheckSupported cloudhealth,hcl
.NOTES
	Idea        :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5.1, VSAN 6.6
	Version 1.0 :: 26-Apr-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/04/managing-silencing-vsan-health-checks-using-powercli.html#more-22754
#>
	
	Param (
		[Parameter(Mandatory = $false)]
		### PS C:\> "'" + ((Get-VSANHealthCheckGroup).GroupId -join "', '") + "'"
		[ValidateSet('cloudhealth', 'cluster', 'data', 'encryption', 'hcl', 'limits', 'network', 'perfsvc', 'physicaldisks', 'stretchedcluster', 'iscsi')]
		[string[]]$TestGroupId
	)
	
	$prop = @('TestId', 'TestName', 'GroupName')
	$vchs = Get-VsanView -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system"
	$result = $vchs.VsanQueryAllSupportedHealthChecks() | sort -Property GroupName, TestId
	
	if ($PSBoundParameters.ContainsKey('TestGroupId')) { $result | ? { $TestGroupId -contains $_.GroupId } | select $prop }
	else { $result | select $prop }
	
} #EndFunction Get-VSANHealthCheckSupported

Function Get-VSANHealthCheckSkipped
{
	
<#
.SYNOPSIS
	Get skipped vSAN Health Checks.
.DESCRIPTION
    This function retreives the list of vSAN Health Checks that have been silenced.
.PARAMETER VsanCluster
    Specifies a vSAN Cluster object(s), returned by Get-Cluster cmdlet.
.EXAMPLE
	PS C:\> Get-VSANHealthCheckSkipped -Cluster (Get-Cluster VSAN-Cluster) -Verbose
.EXAMPLE
    PS C:\> Get-Cluster |Get-VSANHealthCheckSkipped |sort GroupName,TestId
.NOTES
	Idea        :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5.1, VSAN 6.6
	Version 1.0 :: 26-Apr-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/04/managing-silencing-vsan-health-checks-using-powercli.html#more-22754
#>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Alias("Cluster")]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$VsanCluster
	)
	
	Begin
	{
		$vchs = Get-VsanView -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system" -Verbose:$false
	}
	Process
	{
		if ($VsanCluster.VsanEnabled)
		{
			$results = $vchs.VsanHealthGetVsanClusterSilentChecks($VsanCluster.Id)
			foreach ($result in $results)
			{
				$supported = Get-VSANHealthCheckSupported |? {$_.TestId -eq $result}
				[pscustomobject]@{
					Cluster = $VsanCluster.Name
					TestId = $result
					TestName = $supported.TestName
					GroupName = $supported.GroupName
				}
			}
		}
		else
		{
			Write-Verbose "The [$($VsanCluster.Name)] cluster is not VSAN Enabled"
		}
	}
	End {}
	
} #EndFunction Get-VSANHealthCheckSkipped

Function Enable-VSANHealthCheckSkipped
{
	
<#
.SYNOPSIS
	Enable skipped vSAN Health Check(s).
.DESCRIPTION
    This function enables the vSAN Health Checks that have been silenced (skipped).
.PARAMETER Cluster
    Specifies the name of a vSAN Cluster.
.PARAMETER TestId
	Specifies the vSAN Health Check Id to enable.
.EXAMPLE
	PS C:\> Get-Cluster VSAN-Cluster |Get-VSANHealthCheckSkipped |Enable-VSANHealthCheckSkipped
.EXAMPLE
    PS C:\> Get-Cluster |Get-VSANHealthCheckSkipped |? {$_.GroupName -eq 'Hardware compatibility'} |Enable-VSANHealthCheckSkipped -Confirm:$false -Verbose
	Enable all silenced vSAN Health Checks that belong to certain Group (Category) with no confirmation dialog.
.EXAMPLE
	PS C:\> Get-Cluster |Get-VSANHealthCheckSkipped
	Review the changes after execution.
.NOTES
	Idea        :: William Lam @lamw
	Author      :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5.1, VSAN 6.6
	Version 1.0 :: 26-Apr-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/04/managing-silencing-vsan-health-checks-using-powercli.html#more-22754
#>	
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	[Alias("Enable-VSANHealthCheck")]
	Param (
		[Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[string]$Cluster
		 ,
		[Parameter(Mandatory, ValueFromPipelineByPropertyName)]
		[string]$TestId
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$WarningPreference = 'SilentlyContinue'
		$vchs = Get-VsanView -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system" -Verbose:$false
	} #EndBegin
	
	Process
	{
		if ($PSCmdlet.ShouldProcess("Cluster [$Cluster]", "Enable skipped vSAN Health Check [$TestId]"))
		{
			Try
			{
				$removeSilentChecks = $vchs.VsanHealthSetVsanClusterSilentChecks((Get-Cluster $Cluster -Verbose:$false).Id, $null, $TestId)
			}
			Catch
			{
				("{0}" -f $Error.Exception.Message).ToString()
			}
		}
	} #EndProcess
	
	End { }
	
} #EndFunction Enable-VSANHealthCheckSkipped

Function Disable-VSANHealthCheck
{
	
<#
.SYNOPSIS
	Disable vSAN Health Check(s).
.DESCRIPTION
    This function skips (silences) the vSAN Health Checks.
.PARAMETER VsanCluster
    Specifies a vSAN Cluster object(s), returned by Get-Cluster cmdlet.
.PARAMETER TestId
	Specifies the vSAN Health Check Id to disable.
.EXAMPLE
	PS C:\> Get-VSANHealthCheckSupported |Disable-VSANHealthCheck (Get-Cluster) -Confirm:$false -Verbose
	Disable !ALL! available vSAN Health Checks on !ALL! VSAN enabled clusters with no confirmation.
	Use in LAB environments only!
.EXAMPLE
	PS C:\> Get-VSANHealthCheckSupported -TestGroupId perfsvc,hcl,limits |Disable-VSANHealthCheck (Get-Cluster VSAN-Cluster)
	Disable all vSAN Health Checks that belong to the certain groups (categories).
.EXAMPLE
    PS C:\> Get-Cluster VSAN-Cluster |Get-VSANHealthCheckSkipped
	Review the changes after execution.
.NOTES
	Idea        :: William Lam @lamw
	Author      :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5.1, VSAN 6.6
	Version 1.0 :: 26-Apr-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/04/managing-silencing-vsan-health-checks-using-powercli.html#more-22754
#>	
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	Param (
		[Parameter(Mandatory, Position = 0)]
		[Alias("Cluster")]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster[]]$VsanCluster
		 ,
		[Parameter(Mandatory, ValueFromPipelineByPropertyName)]
		[string]$TestId
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$WarningPreference = 'SilentlyContinue'
		$vchs = Get-VsanView -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system" -Verbose:$false
	} #EndBegin
	
	Process
	{
		foreach ($CL in $VsanCluster)
		{
			if ($CL.VsanEnabled)
			{
				if ($PSCmdlet.ShouldProcess("Cluster [$($CL.Name)]", "Disable vSAN Health Check [$TestId]"))
				{
					Try
					{
						$addSilentChecks = $vchs.VsanHealthSetVsanClusterSilentChecks($CL.Id, $TestId, $null)
					}
					Catch
					{
						("{0}" -f $Error.Exception.Message).ToString()
					}
				}
			}
		}
	} #EndProcess
	
	End { }
	
} #EndFunction Disable-VSANHealthCheck

Function Get-VSANSmartData
{
	
<#
.SYNOPSIS
	Get SMART drive data.
.DESCRIPTION
    This function retreives S.M.A.R.T. (Self Monitoring, Analysis & Reporting Technology) drive data.
.PARAMETER VsanCluster
    Specifies a vSAN Cluster object(s), returned by Get-Cluster cmdlet.
.EXAMPLE
	PS C:\> Get-Cluster VSAN-Cluster |Get-VSANSmartData -Verbose
.EXAMPLE
    PS C:\> Get-Cluster |Get-VSANSmartData |ft -au
.NOTES
	Idea        :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5.1, VSAN 6.6
	Version 1.0 :: 26-Apr-2017 :: [Release] :: Publicly available
.LINK
	http://www.virtuallyghetto.com/2017/04/smart-drive-data-now-available-using-vsan-management-6-6-api.html
#>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Alias("Cluster")]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$VsanCluster
	)
	
	Begin
	{
		$vchs = Get-VsanView -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system" -Verbose:$false
	}
	Process
	{
		if ($VsanCluster.VsanEnabled)
		{
			$results = $vchs.VsanQueryVcClusterSmartStatsSummary($VsanCluster.Id)
			
			foreach ($VMHost in $results)
			{
				foreach ($SmartStat in ($VMHost.SmartStats | ? {$null -ne $_.Stats }))
				{
					foreach ($stat in $SmartStat)
					{
						[pscustomobject]@{
							Cluster = $VsanCluster.Name
							VMHost = $VMHost.Hostname
							Disk = $SmartStat.Disk
							Parameter = $stat.Parameter
							Value = $stat.Value
							Threshold = $stat.Threshold
							Worst = $stat.Worst
						}
					}
				}
			}
		}
		else
		{
			Write-Verbose "The [$($VsanCluster.Name)] cluster is not VSAN Enabled"
		}
	}
	End { }
	
} #EndFunction Get-VSANSmartData

Function Get-VSANHealthSummary
{
	
<#
.SYNOPSIS
	Fetch vSAN Cluster Health Status.
.DESCRIPTION
    This function performs a cluster wide health check across all types of Health Checks.
.PARAMETER VsanCluster
    Specifies a vSAN Cluster object(s), returned by Get-Cluster cmdlet.
.PARAMETER FetchFromCache
	If specified the results are returned from cache directly instead of running the full health check.
.PARAMETER SummaryLevel
	Specifies Health Check sets. If Strict level selected, the Best Practices Health Checks will be taken.
.EXAMPLE
	PS C:\> Get-Cluster VSAN-Cluster |Get-VSANHealthSummary Strict -Verbose
.EXAMPLE
    PS C:\> Get-Cluster |Get-VSANHealthSummary -FetchFromCache |ft -Property cluster,*health -au
.NOTES
	Author      :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5.1, VSAN 6.6
	Version 1.0 :: 27-Apr-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2017/05/08/vsan-health-check
#>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Alias("Cluster")]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$VsanCluster
		 ,
		[Parameter(Mandatory = $false)]
		[Alias("Cache")]
		[switch]$FetchFromCache
		 ,
		[Parameter(Mandatory = $false, Position = 0)]
		[ValidateSet("Default", "Strict")]
		[Alias("Level")]
		[string]$SummaryLevel = 'Default'
	)
	
	Begin
	{
		$vchs = Get-VsanView -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system" -Verbose:$false
		$fromCache = if ($FetchFromCache) { $true } else { $false }
		$perspective = if ($SummaryLevel -eq 'Default') { 'defaultView' } else { 'deployAssist' }
		$FormatDate = "dd'/'MM'/'yyyy HH':'mm':'ss"
	}
	Process
	{
		if ($VsanCluster.VsanEnabled)
		{
			$result = $vchs.VsanQueryVcClusterHealthSummary($VsanCluster.Id, 2, $null, $true, $null, $fromCache, $perspective)
			
			$NetworkHealth = if ($result.NetworkHealth.IssueFound) {'Yellow'} else {'Green'}
			
			$summary = [pscustomobject]@{
				Cluster = $VsanCluster.Name
				OverallHealth = (Get-Culture).TextInfo.ToTitleCase($result.OverallHealth)
				OverallHealthDescr = $result.OverallHealthDescription
				Timestamp = (Get-Date $result.Timestamp).ToLocalTime().ToString($FormatDate)
				VMHealth = (Get-Culture).TextInfo.ToTitleCase($result.VmHealth.OverallHealthState)
				NetworkHealth = $NetworkHealth
				DiskHealth = (Get-Culture).TextInfo.ToTitleCase($result.PhysicalDisksHealth.OverallHealth)
				DiskSpaceHealth = (Get-Culture).TextInfo.ToTitleCase($result.LimitHealth.DiskFreeSpaceHealth)
				HclDbHealth = (Get-Culture).TextInfo.ToTitleCase($result.HclInfo.HclDbAgeHealth)
				HclDbTimestamp = (Get-Date $result.HclInfo.HclDbLastUpdate).ToLocalTime().ToString($FormatDate)
			}
			
			if ($null -ne $result.ClusterStatus.UntrackedHosts) { $summary | Add-Member -MemberType NoteProperty -Name VMHostUntracked -Value $result.ClusterStatus.UntrackedHosts }
			if ($null -ne $result.PhysicalDisksHealth.ComponentsWithIssues) { $summary | Add-Member -MemberType NoteProperty -Name DiskProblem -Value $result.PhysicalDisksHealth.ComponentsWithIssues }
			$summary
		}
		else
		{
			Write-Verbose "The [$($VsanCluster.Name)] cluster is not VSAN Enabled"
		}
	}
	End { }
	
} #EndFunction Get-VSANHealthSummary

Function Invoke-VSANHealthCheck
{
	
<#
.SYNOPSIS
	Run vSAN Cluster Health Test.
.DESCRIPTION
    This function performs a cluster wide health check across all types of Health Checks.
.PARAMETER VsanCluster
    Specifies a vSAN Cluster object(s), returned by Get-Cluster cmdlet.
.PARAMETER Level
	Specifies Health Check tests level. Available levels are Group or Test level.
.PARAMETER HideGreen
	If specified, Green or Skipped Health Checks will be removed from the resultant report.
.EXAMPLE
	PS C:\> Get-Cluster |Invoke-VSANHealthCheck -Verbose |sort Health
.EXAMPLE
    PS C:\> Get-Cluster |Invoke-VSANHealthCheck -Level Test |select * -exclude descr* |sort TestGroup,Test |ft -au
.EXAMPLE
    PS C:\> Get-Cluster VSAN-Cluster |Invoke-VSANHealthCheck Test -HideGreen |sort Health
.NOTES
	Author      :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5.1, VSAN 6.6
	Version 1.0 :: 30-Apr-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2017/05/08/vsan-health-check
#>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Alias("Cluster")]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$VsanCluster
		 ,
		[Parameter(Mandatory = $false, Position = 0)]
		[ValidateSet("Group", "Test")]
		[string]$Level = 'Group'
		 ,
		[Parameter(Mandatory = $false)]
		[switch]$HideGreen
	)
	
	Begin
	{
		$vchs = Get-VsanView -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system" -Verbose:$false
	}
	Process
	{
		if ($VsanCluster.VsanEnabled)
		{
			$result = $vchs.VsanQueryVcClusterHealthSummary($VsanCluster.Id, 2, $null, $true, $null, $false, 'defaultView')
			
			if ($Level -eq 'Group') {
				foreach ($Group in $result.Groups) {
					$obj = [pscustomobject] @{
						Cluster = $VsanCluster.Name
						TestGroup = $Group.GroupName
						Health = (Get-Culture).TextInfo.ToTitleCase($Group.GroupHealth)
					}
					if ($PSBoundParameters.ContainsKey('HideGreen'))
					{
						if ('green', 'skipped' -notcontains $obj.Health) { $obj }
					}
					else { $obj }
				}
			}
			else
			{
				foreach ($Group in $result.Groups)
				{
					foreach ($Test in $Group.GroupTests)
					{
						$obj = [pscustomobject] @{
							Cluster = $VsanCluster.Name
							TestGroup = $Group.GroupName
							Test = $Test.TestName
							Description = $Test.TestShortDescription
							Health = (Get-Culture).TextInfo.ToTitleCase($Test.TestHealth)
						}
						if ($PSBoundParameters.ContainsKey('HideGreen'))
						{
							if ('green', 'skipped' -notcontains $obj.Health) { $obj }
						}
						else { $obj }
					}
				}
			}
		}
		else
		{
			Write-Verbose "The [$($VsanCluster.Name)] cluster is not VSAN Enabled"
		}
	}
	End { }
	
} #EndFunction Invoke-VSANHealthCheck

Function Get-VSANCapability
{
	
<#
.SYNOPSIS
	Get vSAN capabilities.
.DESCRIPTION
    This function retreives vSAN capabilities for VCenter/Cluster(s)/VMHost(s).
.PARAMETER Cluster
    Specifies a Cluster object(s), returned by Get-Cluster cmdlet.
.PARAMETER Capability
	Specifies capabilities to filter out.
.EXAMPLE
    PS C:\> Get-Cluster |Get-VSANCapability
.EXAMPLE
    PS C:\> Get-Cluster VSAN-Cluster |Get-VSANCapability
.EXAMPLE
    PS C:\> Get-Cluster VSAN-Cluster |Get-VSANCapability -Capability allflash
.EXAMPLE
    PS C:\> Get-Cluster |Get-VSANCapability allflash, stretchedcluster, encryption
.NOTES
	Author      :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5.1 | PowerShell 4.0 | VC 6.0U2
	Version 1.0 :: 18-Jul-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com
#>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$Cluster
		 ,
		[Parameter(Mandatory = $false, Position = 0)]
		[ValidateSet('throttleresync', 'allflash', 'upgrade', 'decomwhatif', 'objectidentities',
			'clusterconfig', 'stretchedcluster', 'configassist', 'unicastmode', 'iscsitargets',
			'capability', 'witnessmanagement', 'cloudhealth', 'firmwareupdate', 'encryption',
			'nestedfd', 'dataefficiency', 'perfsvcverbosemode', 'vumintegration', IgnoreCase = $false)]
		[string[]]$Capability
	)
	
	Begin
	{
		$WarningPreference = 'SilentlyContinue'
		
		$vccs = Get-VsanView -Id 'VsanCapabilitySystem-vsan-vc-capability-system' -Verbose:$false
		
		$VsanCapabilityDef = @{
			'throttleresync' = 'Throttle Resync Traffic';
			'allflash' = 'All-Flash Support';
			'upgrade' = 'Upgrade';
			'decomwhatif' = 'Decommission WhatIf';
			'objectidentities' = 'Object Identities';
			'clusterconfig' = 'Cluster Config';
			'stretchedcluster' = 'Stretched Cluster';
			'configassist' = 'Configuration Assist';
			'unicastmode' = 'Unicast Mode';
			'iscsitargets' = 'iSCSI Targets';
			'capability' = 'Capability';
			'witnessmanagement' = 'Witness';
			'cloudhealth' = 'Cloud Health Check';
			'firmwareupdate' = 'Firmware Updates';
			'encryption' = 'Datastore Level Encryption';
			'nestedfd' = 'Nested Fault Domains';
			'dataefficiency' = 'Data Efficiency';
			'perfsvcverbosemode' = 'Performance Service Verbose Mode';
			'vumintegration' = 'VUM Integration';
		}
		
		### Filter out Capabilities ###
		$CapabilityFullName = @()
		$CapabilityFullName += if ($PSBoundParameters.ContainsKey('Capability')) { $Capability | % { $VsanCapabilityDef.$_ } }
		
		### VC Capabilities ###
		$VcName = if ($global:DefaultVIServers.Length -eq 1) { $global:DefaultVIServers.Name } else { Throw "You are connected to more than one VC, please disconnect first" }
		$VcType = if ($global:DefaultVIServers.ExtensionData.Content.About.OsType -match '^linux') { 'VCSA' } else { 'VCenter' }
		
		$VcCapability = $vccs.VsanGetCapabilities($null).Capabilities
		foreach ($VcCPB in $VcCapability)
		{
			$objVC = [pscustomobject] @{
				VIObject = $VcName
				Type = $VcType
				Capability = if ($VsanCapabilityDef.ContainsKey($VcCPB)) { $VsanCapabilityDef.$VcCPB } else { $VcCPB }
			}
			if ($PSBoundParameters.ContainsKey('Capability'))
			{
				if ($CapabilityFullName -contains $objVC.Capability) { $objVC }
			}
			else { $objVC }
		}
	}
	Process
	{
		$ClusterCapability = $vccs.VsanGetCapabilities($Cluster.Id)
		$ClusterCPB, $VMHostCPB = ($ClusterCapability).Where({ $_.Target -match '^ClusterComputeResource' }, 'Split')
		
		### Cluster Capabilities ###
		foreach ($ClCPB in $ClusterCPB.Capabilities)
		{
			$objCluster = [pscustomobject] @{
				VIObject = $Cluster.Name
				Type = if ($Cluster.VsanEnabled) { 'VSANCluster' } else { 'Cluster' }
				Capability = if ($VsanCapabilityDef.ContainsKey($ClCPB)) { $VsanCapabilityDef.$ClCPB } else { $ClCPB }
			}
			if ($PSBoundParameters.ContainsKey('Capability'))
			{
				if ($CapabilityFullName -contains $objCluster.Capability) { $objCluster }
			}
			else { $objCluster }
		}
		
		### VMHost Capabilities ###
		foreach ($VMHost in $VMHostCPB)
		{
			$VMHostName = [regex]::Match((Get-View -Id $VMHost.Target).Name, '^(.+?)(\.|$)').Groups[1].Value
			foreach ($EsxCPB in $VMHostCPB.Capabilities)
			{
				$objVMHost = [pscustomobject] @{
					VIObject = $VMHostName
					Type = 'VMHost'
					Capability = if ($VsanCapabilityDef.ContainsKey($EsxCPB)) { $VsanCapabilityDef.$EsxCPB } else { $EsxCPB }
				}
				if ($PSBoundParameters.ContainsKey('Capability'))
				{
					if ($CapabilityFullName -contains $objVMHost.Capability) { $objVMHost }
				}
				else { $objVMHost }
			}
		}
	}
	End { }
	
} #EndFunction Get-VSANCapability
