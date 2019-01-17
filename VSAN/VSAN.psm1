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
	Version 1.1 :: 20-Jul-2017 :: [Bugfix]  :: The '$global:DefaultVIServers' variable used instead of '$global:DefaultVIServer' to determine VC name
	Version 1.2 :: 20-Jul-2017 :: [Improve] :: The 'Version' property type changed from [string] to [System.Version], the 'Cluster' property added
	Version 1.3 :: 20-Jul-2017 :: [Improve] :: Returned object standardized to [PSCustomObject] data type
	Version 1.4 :: 19-Dec-2018 :: [Improve] :: Added 'Type' property
.LINK
	http://www.virtuallyghetto.com/2017/04/getting-started-wthe-new-powercli-6-5-1-get-vsanview-cmdlet.html
#>
	
	[CmdletBinding()]
	[OutputType([PSCustomObject])]
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
			$ClusterVc = [regex]::Match($VsanCluster.Uid, '@(.+):\d+/').Groups[1].Value
			$result = $vchs.VsanVcClusterQueryVerifyHealthSystemVersions($VsanCluster.Id)			
			$return = $result.HostResults | select Hostname, Version | sort Hostname
			
			### Return Hosts' version ###
			$return | %{
				[pscustomobject] @{
					Cluster = $VsanCluster.Name
					Hostname = $_.Hostname
					Type = 'VMHost'
					Version = [version]$_.Version
				}
			}
			
			### Return VC version ###
			$global:DefaultVIServers | %{
				if ($_.Name -eq $ClusterVc)
				{
					[pscustomobject] @{
						Cluster = $VsanCluster.Name
						Hostname = $_.Name
						Type = 'VC'
						Version = [version]$result.VcVersion
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
.PARAMETER HideGood
	If specified, only thresholded attributes returned.
.EXAMPLE
	PS C:\> Get-Cluster VSAN-Cluster | Get-VSANSmartData -Verbose
.EXAMPLE
	PS C:\> Get-Cluster | Get-VSANSmartData -HideGood
.EXAMPLE
	PS C:\> Get-Cluster | Get-VSANSmartData | ogv -Title 'S.M.A.R.T Data'
.NOTES
   Idea        :: William Lam @lamw
   Edited by   :: Roman Gelman @rgelman75
   Requirement :: PowerCLI 6.5.1, PowerShell 4.0, VSAN 6.6
   Version 1.0 :: 26-Apr-2017 :: [Release] :: Publicly available
   Version 1.1 :: 08-Jan-2019 :: [Bugfix] :: Blank statistics returned
   Version 1.2 :: 09-Jan-2019 :: [Change] :: Added a lot of new properties
   Version 1.3 :: 10-Jan-2019 :: [Change] :: Added -HideGood parameter
.LINK
   http://www.virtuallyghetto.com/2017/04/smart-drive-data-now-available-using-vsan-management-6-6-api.html
#>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Alias("Cluster")]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$VsanCluster
		 ,
		[switch]$HideGood
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
			
			foreach ($VMHost in ($results | sort Hostname))
			{
				$Host = Get-VMHost $VMHost.Hostname -Verbose:$false
				$VMHostName = if ($VMHost.Hostname -match '[a-zA-Z]') { [regex]::Match($VMHost.Hostname, '^(.+?)(\.|$)').Groups[1].Value } else { $VMHost.Hostname }
				
				foreach ($SmartStat in $VMHost.SmartStats.Where{ $null -ne $_.Stats })
				{
					$DiskInfo = $Host.StorageInfo.ExtensionData.StorageDeviceInfo.ScsiLun.Where{ $_.CanonicalName -eq $SmartStat.Disk }
					
					foreach ($Stat in $SmartStat.Stats.Where{ $_.Threshold -ne $null })
					{
						$ParameterType = if ($Stat.Threshold -ne 0)
						{
							'Critical'
							$IsFailed = if ($Stat.Worst -le $Stat.Threshold) { $true } else { $false }
						}
						else
						{
							'Info'
							$IsFailed = $false
						}
						
						$Healthy = if ($Stat.Value -ne 100) { [math]::Round($Stat.Value * 100 / (253 - $Stat.Threshold), 0) } else { 100 }
						
						$return = [pscustomobject]@{
							Cluster = $VsanCluster.Name
							VMHost = $VMHostName
							Disk = $SmartStat.Disk
							IsSSD = $DiskInfo.SSD
							DiskModel = $DiskInfo.Model
							DiskState = $DiskInfo.OperationalState
							Attribute = (Get-Culture).TextInfo.ToTitleCase(($Stat.Parameter -replace 'smart', $null))
							Type = $ParameterType
							Value = $Stat.Value
							Worst = $Stat.Worst
							Threshold = $Stat.Threshold
							'Health%' = $Healthy
							DiskFail = $IsFailed
						}
						if ($HideGood)
						{
							if ($return.DiskFail) { $return }
						}
						else { $return }
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

Function Get-VSANLimit
{
	
<#
.SYNOPSIS
	Get a vSAN cluster limits.
.DESCRIPTION
    This function utilizes vSAN Management API to retrieve
    the exact same information provided by the RVC "vsan.check_limits" command.
.PARAMETER VsanCluster
    Specifies a vSAN Cluster object(s), returned by Get-Cluster cmdlet.
.NOTES
	Idea        :: William Lam @lamw
	Author      :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5.1, VSAN 6.6
	Version 1.0 :: 17-Jan-2018 :: [Release] :: Publicly available
.EXAMPLE
    PS C:\> Get-Cluster VSAN-Cluster | Get-VSANLimit
.EXAMPLE
	PS C:\> Get-Cluster | Get-VSANLimit -Verbose | ft -au
.LINK
	http://www.virtuallyghetto.com/2017/06/how-to-convert-vsan-rvc-commands-into-powercli-andor-other-vsphere-sdks.html
#>	
	
	[CmdletBinding()]
	[Alias("Get-VSANLimits")]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Alias("Cluster")]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$VsanCluster
	)
	
	Begin
	{
		$FunctionName = '{0}' -f $MyInvocation.MyCommand
		Write-Verbose "$FunctionName :: Started at [$(Get-Date)]"
	}
	Process
	{
		if ($VsanCluster.VsanEnabled)
		{
			$VMHosts = ($VsanCluster | Get-VMHost -Verbose:$false | Sort-Object -Property Name)
			
			foreach ($VMHost in $VMHosts)
			{
				$connectionState = $VMHost.ExtensionData.Runtime.ConnectionState
				$vsanEnabled = (Get-View $VMHost.ExtensionData.ConfigManager.VsanSystem -Verbose:$false).Config.Enabled
				
				if ($connectionState -eq "connected" -and $vsanEnabled)
				{
					$vsanInternalSystem = Get-View $VMHost.ExtensionData.ConfigManager.VsanInternalSystem -Verbose:$false
					
					# Fetch RDT Information
					$jsonRdtLsomDom = $vsanInternalSystem.QueryVsanStatistics(@('rdtglobal', 'lsom-node', 'lsom', 'dom', 'dom-objects-counts')) | ConvertFrom-Json
					
					# Process RDT Data Start #
					$rdtAssocs = $jsonRdtLsomDom.'rdt.globalinfo'.assocCount.ToString() + "/" + $jsonRdtLsomDom.'rdt.globalinfo'.maxAssocCount.ToString()
					$rdtSockets = $jsonRdtLsomDom.'rdt.globalinfo'.socketCount.ToString() + "/" + $jsonRdtLsomDom.'rdt.globalinfo'.maxSocketCount.ToString()
					$rdtClients = 0
					foreach ($line in $jsonRdtLsomDom.'dom.clients' | Get-Member)
					{
						# crappy way to iterate through keys ...
						if ($($line.Name) -ne "Equals" -and $($line.Name) -ne "GetHashCode" -and $($line.Name) -ne "GetType" -and $($line.Name) -ne "ToString")
						{
							$rdtClients++
						}
					}
					$rdtOwners = 0
					foreach ($line in $jsonRdtLsomDom.'dom.owners.count' | Get-Member)
					{
						# crappy way to iterate through keys ...
						if ($($line.Name) -ne "Equals" -and $($line.Name) -ne "GetHashCode" -and $($line.Name) -ne "GetType" -and $($line.Name) -ne "ToString")
						{
							$rdtOwners++
						}
					}
					# Process RDT Data End #
					
					# Fetch Component information
					$jsonComponents = $vsanInternalSystem.QueryPhysicalVsanDisks(@('lsom_objects_count', 'uuid', 'isSsd', 'capacity', 'capacityUsed')) | ConvertFrom-Json
					
					# Process Component Data Start #
					$vsanUUIDs = @{ }
					$vsanDiskMgmtSystem = Get-VsanView -Id VimClusterVsanVcDiskManagementSystem-vsan-disk-management-system -Verbose:$false
					$diskGroups = $vsanDiskMgmtSystem.QueryDiskMappings($VMHost.ExtensionData.MoRef)
					foreach ($diskGroup in $diskGroups)
					{
						$mappings = $diskGroup.mapping
						foreach ($mapping in $mappings)
						{
							$ssds = $mapping.ssd
							$nonSsds = $mapping.nonSsd
							
							foreach ($ssd in $ssds)
							{
								$vsanUUIDs.add($ssd.vsanDiskInfo.vsanUuid, $ssd)
							}
							
							foreach ($nonSsd in $nonSsds)
							{
								$vsanUUIDs.add($nonSsd.vsanDiskInfo.vsanUuid, $nonSsd)
							}
						}
					}
					$maxComponents = $jsonRdtLsomDom.'lsom.node'.numMaxComponents
					
					$diskString = ""
					$hostComponents = 0
					foreach ($line in $jsonComponents | Get-Member)
					{
						# crappy way to iterate through keys ...
						if ($($line.Name) -ne "Equals" -and $($line.Name) -ne "GetHashCode" -and $($line.Name) -ne "GetType" -and $($line.Name) -ne "ToString")
						{
							if ($vsanUUIDs.ContainsKey($line.Name))
							{
								$numComponents = ($jsonRdtLsomDom.'lsom.disks'.$($line.Name).info.numComp).ToString()
								$maxCoponents = ($jsonRdtLsomDom.'lsom.disks'.$($line.Name).info.maxComp).ToString()
								$hostComponents += $jsonComponents.$($line.Name).lsom_objects_count
								$usage = ($jsonRdtLsomDom.'lsom.disks'.$($line.Name).info.capacityUsed * 100) / $jsonRdtLsomDom.'lsom.disks'.$($line.Name).info.capacity
								$usage = [Math]::ceiling($usage)
								
								$diskString += $vsanUUIDs.$($line.Name).CanonicalName + ": " + $usage + "% Components: " + $numComponents + "/" + $maxCoponents + "`n"
							}
						}
					}
					# Process Component Data End #
					
					[pscustomobject] @{
						Cluster = $VsanCluster.Name
						VMHost = $VMHost.Name
						RDT = "Assocs: " + $rdtAssocs + "`nSockets: " + $rdtSockets + "`nClients: " + $rdtClients + "`nOwners: " + $rdtOwners
						Disks = "Components: " + $hostComponents + "/" + $maxComponents + "`n" + $diskString
					}
				}
			}
		}
		else
		{
			Write-Verbose "$FunctionName :: The [$($VsanCluster.Name)] cluster is not VSAN Enabled"
		}
	}
	End { Write-Verbose "$FunctionName :: Finished at [$(Get-Date)]" }
	
} #EndFunction Get-VSANLimit

Function Get-VSANUsage
{
	
<#
.SYNOPSIS
	Get VSAN Datastore usage.
.DESCRIPTION
    This function retrieves VSAN Datastore usage for all or specific VM.
.PARAMETER VsanCluster
	Specifies a vSAN Cluster object(s), returned by Get-Cluster cmdlet.
.PARAMETER VM
    Specifies a VM name(s) or VM name pattern to query specifically.
.PARAMETER Credential
	Specifies VMHost credentials for direct connect.
.EXAMPLE
    PS C:\> Get-Cluster | Get-VSANUsage -Verbose | Format-Table -AutoSize
	Get VSAN datastore usage in all VSAN enabled clusters.
.EXAMPLE
    PS C:\> Get-Cluster VSANCluster | Get-VSANUsage -VM vm1, vm2
	Get VSAN datastore usage for two particular VM.
.EXAMPLE
    PS C:\> Get-Cluster VSANCluster | Get-VSANUsage -VM lnx*
	Get VSAN datastore usage for VM, taken by pattern.
.NOTES
	Idea        :: William Lam @lamw (Get-VSANVMDetailedUsage function)
	Author      :: Roman Gelman @rgelman75
	Version 1.0 :: 19-Jul-2018 :: [Release] :: Publicly available
.LINK
	https://www.virtuallyghetto.com/2018/06/retrieving-detailed-per-vm-space-utilization-on-vsan.html
#>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[Alias("Cluster")]
		[VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]$VsanCluster
		 ,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullOrEmpty()]
		[string[]]$VM
		 ,
		[Parameter(Mandatory = $false)]
		[pscredential]$Credential = $(Get-Credential -Message "VMHost Credentials")
	)
	
	Begin
	{
		$FunctionName = '{0}' -f $MyInvocation.MyCommand
		$rgxVsanPath = '\[(?<Datastore>vsanDatastore)\]\s(?<Folder>.+)/(?<File>.+)$'
		if ($PSBoundParameters.ContainsKey('VM')) { $VM = if ($VM -match '\*') { @((Get-VM $VM -Location $VsanCluster -Verbose:$false).Name) } else { $VM } }
	}
	Process
	{
		if ($VsanCluster.VsanEnabled)
		{
			$clusterView = Get-View -Verbose:$false -ViewType ClusterComputeResource -Property Name, Host -Filter @{ "name" = "$($VsanCluster.Name)" }
			
			foreach ($vmhost in $($clusterView.Host))
			{
				$vmhostView = Get-View $vmhost -Verbose:$false -Property Name
				$esxiConnection = Try { Connect-VIServer -Server $vmhostView.name -Credential $Credential -ErrorAction Stop }
				Catch { Write-Verbose "$FunctionName :: Failed to connect to the [$($VsanCluster.Name)\$($vmhostView.Name)] VMHost"; Break }
				
				$vos = Get-VSANView -Id "VsanObjectSystem-vsan-object-system" -Server $esxiConnection -Verbose:$false
				$identities = $vos.VsanQueryObjectIdentities($null, $null, $null, $false, $true, $true)
				
				$json = $identities.RawData | ConvertFrom-Json
				$jsonResults = $json.identities.vmIdentities
				
				foreach ($vmInstance in $jsonResults)
				{
					$identities = $vmInstance.objIdentities
					foreach ($identity in $identities | Sort-Object -Property "type", "description")
					{
						### Retrieve the VM Name ###
						if ($identity.type -eq "namespace")
						{
							$vsanIntSys = Get-View (Get-VMHost -Server $esxiConnection -Verbose:$false).ExtensionData.ConfigManager.vsanInternalSystem -Verbose:$false
							$attributes = ($vsanIntSys.GetVsanObjExtAttrs($identity.uuid)) | ConvertFrom-JSON
							
							foreach ($attribute in $attributes | Get-Member)
							{
								if ("Equals", "GetHashCode", "GetType", "ToString" -notcontains $($attribute.Name))
								{
									$objectID = $attribute.name
									$vmName = $attributes.$($objectID).'User friendly name'
								}
							}
						}
						
						$VsanPath = [regex]::Match($identity.description, $rgxVsanPath)
						
						$return = [pscustomobject] @{
							Cluster = $VsanCluster.Name
							VM = $vmName
							Folder = $VsanPath.Groups['Folder'].Value
							File = $VsanPath.Groups['File'].Value
							Type = $identity.type
							UsedGB = [Math]::Round($identity.physicalUsedB/1GB, 2)
							ReservedGB = [Math]::Round($identity.reservedCapacityB/1GB, 2)
						}
						
						### Filter out a specific VM if provided ###
						if ($PSBoundParameters.ContainsKey('VM')) { if ($VM -icontains $return.VM) { $return } }
						else { $return }
					}
				}
				Disconnect-VIServer -Server $esxiConnection -Confirm:$false -Force -Verbose:$false
			}
		}
		else
		{
			Write-Verbose "$FunctionName :: The [$($VsanCluster.Name)] cluster is not VSAN Enabled"
		}
	}
	End { }
	
} #EndFunction Get-VSANUsage
