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
	Version 1.0 :: 26-Apr-2017 :: [Release]
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
	Version 1.0 :: 26-Apr-2017 :: [Release]
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
    Specifies a vSAN Cluster object, returned by Get-Cluster cmdlet.
.EXAMPLE
	PS C:\> Get-VSANHealthCheckSkipped -Cluster (Get-Cluster VSAN-Cluster) -Verbose
.EXAMPLE
    PS C:\> Get-Cluster |Get-VSANHealthCheckSkipped
.NOTES
	Idea        :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5.1, VSAN 6.6
	Version 1.0 :: 26-Apr-2017 :: [Release]
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
		if ($_.VsanEnabled)
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
			Write-Verbose "[$($VsanCluster.Name)] cluster is not VSAN Enabled"
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
	Version 1.0 :: 26-Apr-2017 :: [Release]
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
    Specifies a vSAN Cluster object, returned by Get-Cluster cmdlet.
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
	Version 1.0 :: 26-Apr-2017 :: [Release]
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
    This function retreives SMART (Self Monitoring, Analysis & Reporting Technology) drive data.
.PARAMETER VsanCluster
    Specifies a vSAN Cluster object, returned by Get-Cluster cmdlet.
.EXAMPLE
	PS C:\> Get-Cluster VSAN-Cluster |Get-VSANSmartData -Verbose
.EXAMPLE
    PS C:\> Get-Cluster |Get-VSANSmartData |ft -au
.NOTES
	Idea        :: William Lam @lamw
	Edited by   :: Roman Gelman @rgelman75
	Requirement :: PowerCLI 6.5.1, VSAN 6.6
	Version 1.0 :: 26-Apr-2017 :: [Release]
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
		if ($_.VsanEnabled)
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
			Write-Verbose "[$($VsanCluster.Name)] cluster is not VSAN Enabled"
		}
	}
	End { }
	
} #EndFunction Get-VSANSmartData
