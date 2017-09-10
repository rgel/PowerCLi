Class SdrsRule
{
	[ValidateNotNullOrEmpty()][string]$DatastoreCluster
	[ValidateNotNullOrEmpty()][int]$RuleId
	[ValidateNotNullOrEmpty()][string]$RuleType
	[ValidateNotNullOrEmpty()][string]$RuleName
	[ValidateNotNullOrEmpty()][boolean]$Enabled
	[ValidateNotNullOrEmpty()][string[]]$VM
	[pscustomobject[]]$HardDisks
}

Function Get-SdrsCluster
{
	
<#
.SYNOPSIS
	Get SDRS Cluster settings.
.DESCRIPTION
	This function retrieves Storage DRS Cluster settings.
.PARAMETER DatastoreCluster
	Specifies Datastore Cluster object(s), returned by Get-DatastoreCluster cmdlet.
.PARAMETER VMOverrides
	If specified, only Virtual Machine overrided settings of SDRS cluster returned.
.EXAMPLE
	PS C:\> Get-DatastoreCluster PROD |Get-SdrsCluster
	Get single SDRS cluster settings.
.EXAMPLE
	PS C:\> Get-DatastoreCluster |Get-SdrsCluster |ft -au
	Get all available SDRS clusters' settings.
.EXAMPLE
	PS C:\> Get-DatastoreCluster LAB* |Get-SdrsCluster -VMSettings |sort AutomationLevel |ft -au
	Get VMSettings for matched SDRS clusters.
.EXAMPLE
	PS C:\> Get-DatastoreCluster DEV |Get-SdrsCluster -VMSettings |? {!$_.KeepVMDKsTogether}
	Get VMs allowed to distribute their HardDisks across Datastores within SRDS cluster.
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5.1
	Platform    :: Tested on vSphere 5.5 | VCenter 5.5U2
	Requirement :: PowerShell 3.0 | PowerCLi 5.0
	Version 1.0 :: 13-Aug-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2017/08/16/sdrs-powercli-part1
#>
	
	[CmdletBinding()]
	[Alias("Get-ViMSdrsCluster")]
	[OutputType([PSCustomObject])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.DatastoreCluster]$DatastoreCluster
		 ,
		[Parameter(Mandatory = $false)]
		[Alias("VMSettings")]
		[switch]$VMOverrides
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$WarningPreference = 'SilentlyContinue'
	}
	Process
	{
		Try
		{
			$DscView = Get-View -VIObject $DatastoreCluster
			$DscViewConfig = $DscView.PodStorageDrsEntry.StorageDrsConfig.PodConfig
			
			### Cluster Default AutomationLevel ###
			$Automation = switch ($DscViewConfig.DefaultVmBehavior)
			{
				'automated' { 'Fully Automated'; Break }
				'manual' { 'Manual Mode'; Break }
				default { $DscViewConfig.DefaultVmBehavior }
			}
			
			### Cluster Default Intra-Vm Affinity ###
			$DefaultAffinity = if ($DscViewConfig.DefaultIntraVmAffinity) { 'KeepTogether' }
			else { 'DistributeAcrossDatastores' }
			
			if ($VMOverrides)
			{
				foreach ($VMConfig in $DscView.PodStorageDrsEntry.StorageDrsConfig.VmConfig)
				{
					$VmAutomation = switch ($VMConfig.Behavior)
					{
						'automated' { 'Fully Automated'; Break }
						'manual' { 'Manual Mode'; Break }
						'' { "Default ($Automation)" }
						default { $VMConfig.Behavior }
					}
					
					$Enabled = if ($VMConfig.IntraVmAntiAffinity) { $VMConfig.IntraVmAntiAffinity.Enabled }
					else { $null; if ($VMConfig.Enabled -eq $false) { $VmAutomation = 'Disabled' } }
					
					$Source = switch ($Enabled)
					{
						$true { 'Active Rule'; Break }
						$false { 'Disabled Rule'; Break }
						$null { 'Override' }
					}
					
					$IntraVmAffinity = if ($VMConfig.IntraVmAffinity -eq $null) { "Default ($($DscViewConfig.DefaultIntraVmAffinity))" }
					else { $VMConfig.IntraVmAffinity }
					
					$return = [pscustomobject] @{
						DatastoreCluster = $DscView.Name
						VM = (Get-View -Id $VMConfig.Vm).Name
						Source = $Source
						AutomationLevel = $VmAutomation
						KeepVMDKsTogether = $IntraVmAffinity
					}
					if ($return.AutomationLevel -imatch '^default' -and $return.KeepVMDKsTogether -imatch '^default') { } else { $return }
				}
			}
			else
			{
				### AdvancedOptions ###
				$AdvOpt = if ($DscViewConfig.Option)
				{
					$Options = $DscViewConfig.Option.GetEnumerator() | % { [string]$_.Key + ' = ' + [string]$_.Value }
					$Options -join '; '
				}
				else
				{
					$null
				}
				
				### Usage% ###
				$UsagePercent = [math]::Round(($DscView.Summary.Capacity - $DscView.Summary.FreeSpace)/$DscView.Summary.Capacity * 100, 0)
				
				### CheckImbalanceEvery ###
				$CheckImbalancePeriod = $DscViewConfig.LoadBalanceInterval / 60
				$CheckImbalanceUnits = if ($CheckImbalancePeriod -eq 1)
				{
					'Hour'
				}
				elseif (2 .. 23 -contains $CheckImbalancePeriod)
				{
					'Hours'
				}
				else
				{
					'Days'
					$CheckImbalancePeriod = [math]::Round($CheckImbalancePeriod / 24, 1)
				}
				
				[pscustomobject] @{
					DatastoreCluster = $DscView.Name
					CapacityTB = [math]::Round($DscView.Summary.Capacity/1TB, 1)
					FreeSpaceTB = [math]::Round($DscView.Summary.FreeSpace/1TB, 1)
					'Usage%' = New-PercentageBar -Percent $UsagePercent
					TurnOnSDRS = $DscViewConfig.Enabled
					AutomationLevel = $Automation
					AdvancedOptions = $AdvOpt
					EnableIOMetric = $DscViewConfig.IoLoadBalanceEnabled
					'UtilizedSpace%' = New-PercentageBar -Percent $DscViewConfig.SpaceLoadBalanceConfig.SpaceUtilizationThreshold
					IOLatency = "$($DscViewConfig.IoLoadBalanceConfig.IoLatencyThreshold)ms " + (New-PercentageBar -Percent $DscViewConfig.IoLoadBalanceConfig.IoLatencyThreshold -NoPercent)
					'MinSpaceUtilizationDifference%' = New-PercentageBar -Percent $DscViewConfig.SpaceLoadBalanceConfig.MinSpaceUtilizationDifference
					CheckImbalanceEvery = "$CheckImbalancePeriod $CheckImbalanceUnits"
					IOImbalanceThreshold = "Aggressive " + (New-PercentageBar -Value $DscViewConfig.IoLoadBalanceConfig.IoLoadImbalanceThreshold -MaxValue 25 -NoPercent) + " Conservative"
					DefaultIntraVmAffinity = $DefaultAffinity
				}
			}
		}
		Catch
		{
			"{0}" -f $Error.Exception.Message
		}
	}
	End { }
	
} #EndFunction Get-SdrsCluster

Function Set-SdrsCluster
{
	
<#
.SYNOPSIS
	Set SDRS Cluster settings.
.DESCRIPTION
	This function configures Storage DRS Cluster.
.PARAMETER DatastoreCluster
	Specifies Datastore Cluster object(s), returned by Get-DatastoreCluster cmdlet.
.PARAMETER ShowBeforeState
	If specified, SDRS cluster state will be taken before applying changes.
.PARAMETER DefaultIntraVmAffinity
	Specifies Default Intra-Vm Affinity policy (VMDK affinity) for SDRS Cluster.
.PARAMETER TurnOnSRDS
	Enable/disable Storage DRS feature.
.PARAMETER AutomationLevel
	Specifies SDRS Automation Level.
.PARAMETER EnableIOMetric
	If $true will enable I/O Metric for SRDS recommendations.
.PARAMETER UtilizedSpace
	Specifies SDRS Runtime Threshold on Utilized Space (%).
.PARAMETER IOLatency
	Specifies SRDS Runtime Threshold on I/O Latency (ms).
.PARAMETER MinSpaceUtilizationDifference
	Specifies utilization difference between source and destination until which no SDRS recommendations (%).
.PARAMETER CheckImbalanceEveryMin
	Specifies how frequently to check imbalance (min).
.PARAMETER IOImbalanceThreshold
	Specifies amount of imbalance that SDRS should tolerate.
	1 - the most Aggressive (correct small imbalance), 25 - the most Conservative.
.EXAMPLE
	PS C:\> Get-DatastoreCluster $DatastoreClusterName |Set-SdrsCluster
	Set Default Intra-Vm Affinity policy to DistributeAcrossDatastores on single DatastoreCluster.
.EXAMPLE
	PS C:\> Get-DatastoreCluster -Location $DatacenterName |Set-SdrsCluster -TurnOnSDRS:$false
	Disable SDRS on all DatastoreClusters in a Datacenter.
.EXAMPLE
	PS C:\> Get-DatastoreCluster |Set-SdrsCluster -AutomationLevel FullyAutomated -Confirm:$false
	Set Automation Level on all SRDS Clusters in Inventory.
.EXAMPLE
	PS C:\> Get-DatastoreCluster $DatastoreClusterName |Set-SdrsCluster -EnableIOMetric:$true 
	Enable I/O Metric for SRDS recommendations and set default Runtime Thresholds.
.EXAMPLE
	PS C:\> Get-DatastoreCluster |Set-SdrsCluster -Option IgnoreAffinityRulesForMaintenance -Value 1
	Set SRDS Automation Advanced Option for all available SDRS Clusters.
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5.1
	Platform    :: Tested on vSphere 5.5 | VCenter 5.5U2
	Requirement :: PowerShell 3.0 | PowerCLi 5.0
	Version 1.0 :: 11-Jul-2017 :: [Release] :: Publicly available
	Version 1.1 :: 17-Aug-2017 :: [Bugfix] :: Alias renamed from Get-ViMSdrsCluster to Set-ViMSdrsCluster
.LINK
	https://ps1code.com/2017/08/16/sdrs-powercli-part1
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess, DefaultParameterSetName = 'VMAFFINITY')]
	[Alias("Set-ViMSdrsCluster")]
	[OutputType([PSCustomObject])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.DatastoreCluster]$DatastoreCluster
		 ,
		[Parameter(Mandatory = $false)]
		[switch]$ShowBeforeState
		 ,
		[Parameter(Mandatory = $false, ParameterSetName = 'VMAFFINITY')]
		[ValidateSet("KeepTogether", "DistributeAcrossDatastores")]
		[string]$DefaultIntraVmAffinity = 'DistributeAcrossDatastores'
		 ,
		[Parameter(Mandatory, ParameterSetName = 'SDRSONOFF')]
		[boolean]$TurnOnSDRS
		 ,
		[Parameter(Mandatory, ParameterSetName = 'AUTOMATION')]
		[ValidateSet("FullyAutomated", "ManualMode")]
		[string]$AutomationLevel
		 ,
		[Parameter(Mandatory, ParameterSetName = 'RUNTIMERULES')]
		[boolean]$EnableIOMetric
		 ,
		[Parameter(Mandatory = $false, ParameterSetName = 'RUNTIMERULES')]
		[ValidateRange(50, 100)]
		[int]$UtilizedSpace = 80
		 ,
		[Parameter(Mandatory = $false, ParameterSetName = 'RUNTIMERULES')]
		[ValidateRange(5, 100)]
		[int]$IOLatency = 15
		 ,
		[Parameter(Mandatory = $false, ParameterSetName = 'RUNTIMERULES')]
		[ValidateRange(1, 50)]
		[int]$MinSpaceUtilizationDifference = 5
		 ,
		[Parameter(Mandatory = $false, ParameterSetName = 'RUNTIMERULES')]
		[ValidateRange(60, 43200)]
		[int]$CheckImbalanceEveryMin = 480
		 ,
		[Parameter(Mandatory = $false, ParameterSetName = 'RUNTIMERULES')]
		[ValidateRange(1, 25)]
		[int]$IOImbalanceThreshold = 5
		 ,
		[Parameter(Mandatory, ParameterSetName = 'ADVOPT')]
		[string]$Option
		 ,
		[Parameter(Mandatory, ParameterSetName = 'ADVOPT')]
		[string]$Value
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$WarningPreference = 'SilentlyContinue'
		$SRMan = Get-View StorageResourceManager
		
		switch ($PsCmdlet.ParameterSetName)
		{
			'VMAFFINITY' { $Enabled = if ($DefaultIntraVmAffinity -eq 'KeepTogether') { $true } else { $false }; Break }
			'AUTOMATION' { $Automation = if ($AutomationLevel -eq 'FullyAutomated') { 'automated' } else { 'manual' } }
		}
	}
	Process
	{
		if ($ShowBeforeState) { Get-SdrsCluster -DatastoreCluster $DatastoreCluster }
		
		$spec = New-Object VMware.Vim.StorageDrsConfigSpec
		$spec.PodConfigSpec = New-Object VMware.Vim.StorageDrsPodConfigSpec
		
		$ConfirmMsg = switch ($PsCmdlet.ParameterSetName)
		{
			'VMAFFINITY'
			{
				"Set DefaultIntraVmAffinity to [$DefaultIntraVmAffinity]"
				$spec.PodConfigSpec.DefaultIntraVmAffinity = $Enabled
				Break
			}
			'SDRSONOFF'
			{
				if ($TurnOnSDRS) { "Enable Storage DRS" }
				else { "Disable Storage DRS" }
				$spec.PodConfigSpec.Enabled = $TurnOnSDRS
				Break
			}
			'AUTOMATION'
			{
				"Set Automation Level to [$AutomationLevel]"
				$spec.PodConfigSpec.DefaultVmBehavior = $Automation
				Break
			}
			'RUNTIMERULES'
			{
				if ($EnableIOMetric) { "Enable I/O metric and Set Runtime Thresholds" }
				else { "Disable I/O metric and Set Runtime Thresholds" }
				$spec.PodConfigSpec.LoadBalanceInterval = $CheckImbalanceEveryMin
				$spec.PodConfigSpec.IoLoadBalanceConfig = New-Object VMware.Vim.StorageDrsIoLoadBalanceConfig
				$spec.PodConfigSpec.IoLoadBalanceEnabled = $EnableIOMetric
				$spec.PodConfigSpec.IoLoadBalanceConfig.IoLatencyThreshold = $IOLatency
				$spec.PodConfigSpec.IoLoadBalanceConfig.IoLoadImbalanceThreshold = $IOImbalanceThreshold
				$spec.PodConfigSpec.SpaceLoadBalanceConfig = New-Object VMware.Vim.StorageDrsSpaceLoadBalanceConfig
				$spec.PodConfigSpec.SpaceLoadBalanceConfig.SpaceUtilizationThreshold = $UtilizedSpace
				$spec.PodConfigSpec.SpaceLoadBalanceConfig.MinSpaceUtilizationDifference = $MinSpaceUtilizationDifference
				Break
			}
			'ADVOPT'
			{
				"Set Advanced Option [$Option] to Value [$Value]"
				$opSpec = New-Object VMware.Vim.StorageDrsOptionSpec
				$opSpec.Option = New-Object VMware.Vim.OptionValue
				$opSpec.Option.Key = $Option
				$opSpec.Option.Value = $Value
				$spec.PodConfigSpec.Option = $opSpec
			}
		}
		
		if ($PSCmdlet.ShouldProcess("DatastoreCluster [$($DatastoreCluster.Name)]", $ConfirmMsg))
		{
			Try
			{
				$SRMan.ConfigureStorageDrsForPod($DatastoreCluster.Id, $spec, $true)
				Get-SdrsCluster -DatastoreCluster $DatastoreCluster
			}
			Catch
			{
				"{0}" -f $Error.Exception.Message
			}
		}
	}
	End { }
	
} #EndFunction Set-SdrsCluster

Function Add-SdrsAntiAffinityRule
{
	
<#  
.SYNOPSIS
	Create SDRS anti-affinity rules.
.DESCRIPTION
	This function creates Storage DRS anti-affinity rules (VMDK and VM).
.PARAMETER VM
	Specifies one virtual machine for which to create a VMDK SDRS (intra-VM) anti-affinity rule.
.PARAMETER VMGroup
	Specifies two or more virtual machines for which to create a VM SDRS (inter-VM) anti-affinity rule.
.PARAMETER DatastoreCLuster
	Specifies DatastoreCluster where the anti-affinity rule shall be created.
.PARAMETER RuleName
	Specifies the rule name.
.PARAMETER Enabled
	If specified, the rule should be enabled immediately after creation.
.EXAMPLE
	PS C:\> Add-SdrsAntiAffinityRule -VM vm1 -Harddisk 2,3 -DatastoreCluster PROD
	Add intra-VM rule for two VM data disks.
.EXAMPLE
	PS C:\> Get-DatastoreCluster TEST |Add-SdrsAntiAffinityRule -VM vm1 -Enabled
	Add intra-VM rule for all VM disks.
.EXAMPLE
	PS C:\> Get-DatastoreCluster LAB |Add-SdrsAntiAffinityRule -VMGroup VM1, VM2, VM3 -Rule SQL
	Add inter-VM rule for three VM.
.EXAMPLE
	PS C:\> Get-DatastoreCluster PROD |Add-SdrsAntiAffinityRule -VMGroup (Get-VM ntp*) -Rule NetAppAV -Enabled
	Add and enable inter-VM rule.
.NOTES
	Author      :: Luc Dekens @LucD22 (Set-SdrsAntiAffinity - http://www.lucd.info/2013/01/21/automate-your-sdrs-anti-affinity-rules/) 
	Edited      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5.2
	Platform    :: Tested on vSphere 5.5 | VCenter 5.5U2
	Requirement :: PowerShell 5.0
	Version 1.0 :: 24-Aug-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2017/09/06/sdrs-powercli-part2
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	[Alias("Add-ViMSdrsAntiAffinityRule", "New-SdrsAntiAffinityRule")]
	[OutputType([SdrsRule])]
	Param (
		[Parameter(Mandatory, ParameterSetName = 'VMDK')]
		[PSObject]$VM
		 ,
		[Parameter(Mandatory = $false, ParameterSetName = 'VMDK')]
		[ValidateCount(2, 60)]
		[int[]]$Harddisk
		 ,
		[Parameter(Mandatory, ParameterSetName = 'VM')]
		[ValidateCount(2, 64)]
		[PSObject[]]$VMGroup
		 ,
		[Parameter(Mandatory, ValueFromPipeline)]
		[PSObject]$DatastoreCluster
		 ,
		[Parameter(Mandatory = $false)]
		[string]$RuleName
		 ,
		[Parameter(Mandatory = $false)]
		[switch]$Enabled
		 ,
		[Parameter(Mandatory = $false)]
		[switch]$Apply
	)
	
	Begin
	{
		$storMgr = Get-View StorageResourceManager
		$spec = New-Object VMware.Vim.StorageDrsConfigSpec
		$disk = &{ if (!$Harddisk) { 1 .. 60 } else { $Harddisk } }
	}
	Process
	{
		if ($DatastoreCluster -is [string]) { $DatastoreCluster = Get-DatastoreCluster -Name $DatastoreCluster }
		
		switch ($PsCmdlet.ParameterSetName)
		{
			'VM'
			{
				$VMGroup = $VMGroup |% { if ($_ -is [string]) { Get-VM -Name $_ } else { $_ } }
				if (!$RuleName) { Throw "Please supply Rule name by [-RuleName] parameter" }
				$RuleDetails = "Inter-VM Anti-Affinity Rule for $($VMGroup.Count) VM"
				
				if (!$spec.podConfigSpec) { $spec.podConfigSpec = New-Object VMware.Vim.StorageDrsPodConfigSpec }
				$rule = New-Object VMware.Vim.ClusterRuleSpec
				$rule.Operation = "add"
				$rule.Info = New-Object VMware.Vim.ClusterAntiAffinityRuleSpec
				$rule.Info.Enabled = $Enabled
				$rule.Info.Name = $RuleName
				$rule.Info.Vm = $VMGroup |% { $_.ExtensionData.MoRef }
				$spec.podConfigSpec.rule += $rule
			}
			'VMDK'
			{
				if ($VM -is [string]) { $VM = Get-VM -Name $VM }
				$RuleName = if (!$RuleName) { $VM.Name } else { $RuleName }
				
				$vmSpec = New-Object VMware.Vim.StorageDrsVmConfigSpec
				$vmSpec.Operation = "add"
				$vmSpec.Info = New-Object VMware.Vim.StorageDrsVmConfigInfo
				$vmSpec.Info.Vm = $VM.ExtensionData.MoRef
				$vmSpec.Info.Enabled = $true
				$vmSpec.Info.IntraVmAffinity = $false
				$vmSpec.Info.IntraVmAntiAffinity = New-Object VMware.Vim.VirtualDiskAntiAffinityRuleSpec
				$vmSpec.Info.IntraVmAntiAffinity.Enabled = $Enabled
				$vmSpec.Info.IntraVmAntiAffinity.Name = $RuleName
				$vmSpec.Info.IntraVmAntiAffinity.DiskId = &{
					$VM.ExtensionData.Config.Hardware.Device |
					where {
						$_ -is [VMware.Vim.VirtualDisk] -and
						$disk -contains $_.DeviceInfo.Label.Split(' ')[2]
					} | select -ExpandProperty Key
				}
				if ($vmspec.Info.IntraVmAntiAffinity.DiskId.Count -ge 2) { $spec.vmConfigSpec += $vmSpec }
				$RuleDetails = "Intra-VM Anti-Affinity Rule for $($vmspec.Info.IntraVmAntiAffinity.DiskId.Count) HardDisks of VM [$($VM.Name)]"
			}
		}
		
		$Action = if ($Enabled) { 'Add and enable' } else { 'Add' }
		if ($PSCmdlet.ShouldProcess("DatastoreCluster [$($DatastoreCluster.Name)]", "$Action SDRS $RuleDetails"))
		{
			$storMgr.ConfigureStorageDrsForPod($DatastoreCluster.ExtensionData.MoRef, $spec, $true)
			Start-SleepProgress -Second 10
			Get-SdrsAntiAffinityRule -DatastoreCluster (Get-DatastoreCluster $DatastoreCluster.Name) | ? { $_.RuleName -eq $RuleName }
			if ($Apply) { $storMgr.RefreshStorageDrsRecommendation($DatastoreCluster.Id) }
		}
	}
	End { }
	
} #EndFunction Add-SdrsAntiAffinityRule

Function Get-SdrsAntiAffinityRule
{
	
<#
.SYNOPSIS
	Get SDRS anti-affinity rules.
.DESCRIPTION
	This function retrieves Storage DRS anti-affinity rules (VMDK and VM).
.PARAMETER DatastoreCluster
	Specifies SDRS Cluster object(s), returned by Get-DatastoreCluster cmdlet.
.PARAMETER RuleType
	If specified, only rules of particular type will be returned.
.EXAMPLE
	PS C:\> Get-DatastoreCluster PROD |Get-SdrsAntiAffinityRule
.EXAMPLE
	PS C:\> Get-DatastoreCluster LAB |Get-SdrsAntiAffinityRule -RuleType InterVM |? {!$_.Enabled}
.EXAMPLE
	PS C:\> Get-DatastoreCluster TEST |Get-SdrsAntiAffinityRule VMDK |select *, @{N='HDD'; E={'[' + (($_ |select -expand HardDisks).HardDisk -join '] [') + ']'}}
.EXAMPLE
	PS C:\> Get-DatastoreCluster TEST |Get-SdrsAntiAffinityRule VMDK |select *, @{N='HddIndex'; E={'[' + (($_ |select -expand HardDisks).Index -join '] [') + ']'}} |select * -exclude HardDisks
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5.2
	Platform    :: Tested on vSphere 5.5 | VCenter 5.5U2
	Requirement :: PowerShell 5.0
	Version 1.0 :: 24-Aug-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2017/09/06/sdrs-powercli-part2
#>
	
	[CmdletBinding()]
	[Alias("Get-ViMSdrsAntiAffinityRule")]
	[OutputType([SdrsRule])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.DatastoreCluster]$DatastoreCluster
		 ,
		[Parameter(Mandatory = $false, Position = 0)]
		[ValidateSet("InterVM", "VMDK")]
		[string]$RuleType
	)
	
	Begin
	{
		$WarningPreference = 'SilentlyContinue'
	}
	Process
	{
		### Inter-VM rules ###
		if ($RuleType -ne 'VMDK')
		{
			$DatastoreCluster.ExtensionData.PodStorageDrsEntry.StorageDrsConfig.PodConfig.Rule | ? { $_.Vm } | %{
				
				[SdrsRule] @{
					DatastoreCluster = $DatastoreCluster.Name
					RuleId = $_.Key
					RuleType = 'Inter-VM'
					RuleName = $_.Name
					Enabled = $_.Enabled
					VM = ($_.Vm | % { (Get-View -Id $_).Name } | sort)
					HardDisks = $null
				}
			}
		}
		
		### Intra-VM rules ###
		if ($RuleType -ne 'InterVM')
		{
			foreach ($VmConfig in ($DatastoreCluster.ExtensionData.PodStorageDrsEntry.StorageDrsConfig.VmConfig | ? { $_.IntraVmAntiAffinity }))
			{
				$Hdd = @()
				(Get-View -Id $VmConfig.Vm).Config.Hardware.Device | ? { $_ -is [VMware.Vim.VirtualDisk] } | %{
					$Hdd += if ($VmConfig.IntraVmAntiAffinity.DiskId.Contains($_.Key))
					{
						[pscustomobject] @{
							HardDisk = $_.DeviceInfo.Label
							Index = [regex]::Match($_.DeviceInfo.Label, '\d+').Value
							DiskId = $_.Key
							CapacityGB = [Math]::Round($_.CapacityInBytes/1GB, 0)
						}
					}
				}
				
				[SdrsRule] @{
					DatastoreCluster = $DatastoreCluster.Name
					RuleId = $VmConfig.IntraVmAntiAffinity.Key
					RuleType = 'VMDK'
					RuleName = $VmConfig.IntraVmAntiAffinity.Name
					Enabled = $VmConfig.IntraVmAntiAffinity.Enabled
					VM = (Get-View -Id $VmConfig.Vm).Name
					HardDisks = $Hdd
				}
			}
		}
	}
	End { }
	
} #EndFunction Get-SdrsAntiAffinityRule

Function Remove-SdrsAntiAffinityRule
{
	
<#  
.SYNOPSIS
	Delete SDRS anti-affinity rules.
.DESCRIPTION
	This function deletes Storage DRS anti-affinity rules (VMDK and VM).
.PARAMETER SdrsRule
	Specifies SDRS rule, returned by Get-SdrsAntiAffinityRule function.
.EXAMPLE
	PS C:\> Get-DatastoreCluster LAB |Get-SdrsAntiAffinityRule |Remove-SdrsAntiAffinityRule
.EXAMPLE
	PS C:\> Get-DatastoreCluster |Get-SdrsAntiAffinityRule VMDK |? {!$_.Enabled} |Remove-SdrsAntiAffinityRule -Confirm:$false
	Delete all inactive intra-VM SDRS rules in all! SDRS clusters with no confirmation!
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5.2
	Platform    :: Tested on vSphere 5.5 | VCenter 5.5U2
	Requirement :: PowerShell 5.0
	Version 1.0 :: 24-Aug-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2017/09/06/sdrs-powercli-part2
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	[Alias("Remove-ViMSdrsAntiAffinityRule")]
	[OutputType([SdrsRule])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[SdrsRule]$SdrsRule
	)
	
	Begin
	{
		$storMgr = Get-View StorageResourceManager
		$spec = New-Object VMware.Vim.StorageDrsConfigSpec
	}
	Process
	{
		$DatastoreCluster = Get-DatastoreCluster -Name $SdrsRule.DatastoreCluster
		
		if ($SdrsRule.RuleType -eq 'Inter-VM')
		{
			if (!$spec.PodConfigSpec) { $spec.PodConfigSpec = New-Object VMware.Vim.StorageDrsPodConfigSpec }
			
			$rule = New-Object VMware.Vim.ClusterRuleSpec
			$rule.Operation = "remove"
			$rule.RemoveKey = $SdrsRule.RuleId
			$rule.Info = New-Object VMware.Vim.ClusterAntiAffinityRuleSpec
			$rule.Info.Enabled = $SdrsRule.Enabled
			$rule.Info.Key = $SdrsRule.RuleId
			$rule.Info.Name = $SdrsRule.RuleName
			$rule.Info.Vm = $SdrsRule.VM | %{ (Get-VM $_).Id }
			
			$spec.PodConfigSpec.Rule += $rule
		}
		else
		{
			$vmSpec = New-Object VMware.Vim.StorageDrsVmConfigSpec
			$vmSpec.Operation = "remove"
			$vmSpec.RemoveKey = $SdrsRule.RuleId
			$vmSpec.Info = New-Object VMware.Vim.StorageDrsVmConfigInfo
			$vmSpec.Info.Vm = (Get-VM $SdrsRule.VM[0]).Id
			$vmSpec.Info.Enabled = $true
			$vmSpec.Info.IntraVmAffinity = $false
			$vmSpec.Info.IntraVmAntiAffinity = New-Object VMware.Vim.VirtualDiskAntiAffinityRuleSpec
			$vmSpec.Info.IntraVmAntiAffinity.Enabled = $SdrsRule.Enabled
			$vmSpec.Info.IntraVmAntiAffinity.Name = $SdrsRule.RuleName
			$vmSpec.Info.IntraVmAntiAffinity.Key = $SdrsRule.RuleId
			$vmSpec.Info.IntraVmAntiAffinity.DiskId = $SdrsRule.HardDisks.DiskId
			
			$spec.VmConfigSpec += $vmSpec
		}
		
		$RemoveRule = Get-SdrsAntiAffinityRule -DatastoreCluster $DatastoreCluster | ? { $_.RuleId -eq $SdrsRule.RuleId }
		
		if ($PSCmdlet.ShouldProcess("DatastoreCluster [$($DatastoreCluster.Name)]", "Remove $($RemoveRule.RuleType) SDRS Rule [$($RemoveRule.RuleName)]"))
		{
			$storMgr.ConfigureStorageDrsForPod($DatastoreCluster.ExtensionData.MoRef, $spec, $true)
		}
	}
	End
	{
		Start-SleepProgress -Second 10
		Get-SdrsAntiAffinityRule -DatastoreCluster (Get-DatastoreCluster $DatastoreCluster.Name)
	}
	
} #EndFunction Remove-SdrsAntiAffinityRule

Function Set-SdrsAntiAffinityRule
{
	
<#  
.SYNOPSIS
	Configure SDRS anti-affinity rules.
.DESCRIPTION
	This function edits Storage DRS anti-affinity rule(s):
	add/remove VM(s) or VMDK(s), rename or enable/disable rules.
.PARAMETER SdrsRule
	Specifies SDRS rule, returned by Get-SdrsAntiAffinityRule function.
.EXAMPLE
	PS C:\> Get-DatastoreCluster LAB |Get-SdrsAntiAffinityRule InterVM |Set-SdrsAntiAffinityRule -VM vm3 -Action Add
	Add one VM to inter-VM rule.
.EXAMPLE
	PS C:\> Get-DatastoreCluster TEST |Get-SdrsAntiAffinityRule InterVM |Set-SdrsAntiAffinityRule -VM (Get-VM 'vm1[19]') -NewName Rule1 -Enable:$true -Confirm:$false
	Add nine VM (named vm11 to vm19) to inter-VM rule with no confirmation, rename and enable the rule after that.
.EXAMPLE
	PS C:\> Get-DatastoreCluster DEV |Get-SdrsAntiAffinityRule VMDK |Set-SdrsAntiAffinityRule -Enable:$true -HardDisk 2
	Add one HardDisk to intra-VM rule and enable the rule after that.
.EXAMPLE
	PS C:\> Get-DatastoreCluster PROD |Get-SdrsAntiAffinityRule VMDK |Set-SdrsAntiAffinityRule -NewName Rule3 -Enable:$false -Action Remove -HardDisk (2..5 -ne 4)
	Remove HardDisks 2 to 5 excluding 4 from a VMDK rule, rename and disable the rule after that.
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5.2
	Platform    :: Tested on vSphere 5.5 | VCenter 5.5U2
	Requirement :: PowerShell 5.0
	Version 1.0 :: 09-Sep-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2017/09/10/sdrs-powercli-part3
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess, DefaultParameterSetName = 'VMDK')]
	[Alias("Set-ViMSdrsAntiAffinityRule")]
	[OutputType([SdrsRule])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[SdrsRule]$SdrsRule
		 ,
		[Parameter(Mandatory = $false)]
		[string]$NewName
		 ,
		[Parameter(Mandatory = $false)]
		[bool]$Enable
		 ,
		[Parameter(Mandatory, ParameterSetName = 'VM')]
		[PSObject[]]$VM
		 ,
		[Parameter(Mandatory = $false, ParameterSetName = 'VMDK')]
		[ValidateRange(1, 60)]
		[uint16[]]$HardDisk = (1..60)
		 ,
		[Parameter(Mandatory = $false)]
		[ValidateSet('Add', 'Remove')]
		[string]$Action = 'Add'
	)
	
	Begin
	{
		$storMgr = Get-View StorageResourceManager
		$spec = New-Object VMware.Vim.StorageDrsConfigSpec
	}
	Process
	{
		$DatastoreCluster = Get-DatastoreCluster -Name $SdrsRule.DatastoreCluster
		$EditRule = Get-SdrsAntiAffinityRule -DatastoreCluster $DatastoreCluster | ? { $_.RuleId -eq $SdrsRule.RuleId }
		
		if ($SdrsRule.RuleType -eq 'Inter-VM' -and $PSCmdlet.ParameterSetName -eq 'VM')
		{
			if ($PSCmdlet.ShouldProcess("DatastoreCluster [$($DatastoreCluster.Name)]", "Edit $($EditRule.RuleType) SDRS Rule [$($EditRule.RuleName)]"))
			{
				### Regenerate VM Id members list ###
				$AlreadyVM = { $SdrsRule.VM |% { (Get-VM $_).Id } }.Invoke()
				$NewMoRef += foreach ($NewVM in $VM)
				{
					if ($NewVM -is [string]) { (Get-VM $NewVM -ea SilentlyContinue).Id }
					elseif ($NewVM -is [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]) { $NewVM.Id }
					else { }
				}
				if ($Action -eq 'Add') { $NewMoRef |% { if ($AlreadyVM -notcontains $_) { $AlreadyVM.Add($_) } } }
				else { $NewMoRef |% { if ($AlreadyVM -contains $_) { $AlreadyVM.Remove($_) | Out-Null } } }
				
				if ($AlreadyVM.Count -lt 2) { Throw "Oops, [$($SdrsRule.RuleName)] - At least two VM members must remain in Inter-VM rule!" }
				
				if (!$spec.PodConfigSpec) { $spec.PodConfigSpec = New-Object VMware.Vim.StorageDrsPodConfigSpec }
				$rule = New-Object VMware.Vim.ClusterRuleSpec
				$rule.Operation = "edit"
				$rule.Info = New-Object VMware.Vim.ClusterAntiAffinityRuleSpec
				$rule.Info.Enabled = if ($PSBoundParameters.ContainsKey('Enable')) { $Enable } else { $SdrsRule.Enabled }
				$rule.Info.Key = $SdrsRule.RuleId
				$rule.Info.Name = if ($PSBoundParameters.ContainsKey('NewName')) { $NewName } else { $SdrsRule.RuleName }
				$rule.Info.Vm = $AlreadyVM
				$spec.PodConfigSpec.Rule = $rule
				
				$storMgr.ConfigureStorageDrsForPod($DatastoreCluster.ExtensionData.MoRef, $spec, $true)
				Start-SleepProgress -Second 10
				Get-SdrsAntiAffinityRule -DatastoreCluster (Get-DatastoreCluster $DatastoreCluster.Name) | ? { $_.RuleId -eq $SdrsRule.RuleId }
			}
		}
		
		if ($SdrsRule.RuleType -eq 'VMDK' -and $PSCmdlet.ParameterSetName -eq 'VMDK')
		{
			if ($PSCmdlet.ShouldProcess("DatastoreCluster [$($DatastoreCluster.Name)]", "Edit $($EditRule.RuleType) SDRS Rule [$($EditRule.RuleName)]"))
			{
				### Get VM's Index-to-DiskId list ###
				$RuleVM = Get-VM $SdrsRule.VM[0]
				$HddVM = $RuleVM.ExtensionData.Config.Hardware.Device | ? { $_ -is [VMware.Vim.VirtualDisk] } |
				select @{ N = 'Index'; E = { [regex]::Match($_.DeviceInfo.Label, '\d+').Value } },
					   @{ N = 'DiskId'; E = { $_ | select -expand Key } }
				
				### Translate HardDisk Indexes to DiskIds ###
				$Id = @(); foreach ($Index in $HardDisk) { foreach ($Hdd in $HddVM) { if ($Index -eq $Hdd.Index) { $Id += $Hdd.DiskId } } }
				
				### Renew DiskId list ###
				$AlreadyVmdk = { $SdrsRule.HardDisks.DiskId }.Invoke()
				if ($Action -eq 'Add') { $Id |% { if ($AlreadyVmdk -notcontains $_) { $AlreadyVmdk.Add($_) } } }
				else { $Id |% { if ($AlreadyVmdk -contains $_) { $AlreadyVmdk.Remove($_) | Out-Null } } }
				
				if ($AlreadyVmdk.Count -eq 0) { Throw "Oops, [$($SdrsRule.RuleName)] - there is no possible to remove ALL HardDisks from VMDK rule!" }
				
				$vmSpec = New-Object VMware.Vim.StorageDrsVmConfigSpec
				$vmSpec.Operation = "edit"
				$vmSpec.Info = New-Object VMware.Vim.StorageDrsVmConfigInfo
				$vmSpec.Info.Vm = $RuleVM.Id
				$vmSpec.Info.Enabled = $true
				$vmSpec.Info.IntraVmAffinity = $false
				$vmSpec.Info.IntraVmAntiAffinity = New-Object VMware.Vim.VirtualDiskAntiAffinityRuleSpec
				$vmSpec.Info.IntraVmAntiAffinity.Enabled = if ($PSBoundParameters.ContainsKey('Enable')) { $Enable } else { $SdrsRule.Enabled }
				$vmSpec.Info.IntraVmAntiAffinity.Name = if ($PSBoundParameters.ContainsKey('NewName')) { $NewName } else { $SdrsRule.RuleName }
				$vmSpec.Info.IntraVmAntiAffinity.Key = $SdrsRule.RuleId
				$vmSpec.Info.IntraVmAntiAffinity.DiskId = $AlreadyVmdk
				$spec.vmConfigSpec = $vmSpec
					
				$storMgr.ConfigureStorageDrsForPod($DatastoreCluster.ExtensionData.MoRef, $spec, $true)
				Start-SleepProgress -Second 10
				Get-SdrsAntiAffinityRule -DatastoreCluster (Get-DatastoreCluster $DatastoreCluster.Name) | ? { $_.RuleId -eq $SdrsRule.RuleId }
			}
		}
	}
	End { }
	
} #EndFunction Set-SdrsAntiAffinityRule

Function Invoke-SdrsRecommendation
{
	
<#
.SYNOPSIS
	Run Storage DRS.
.DESCRIPTION
	This function runs SDRS cluster recommendations.
.PARAMETER DatastoreCluster
	Specifies Datastore Cluster object(s), returned by Get-DatastoreCluster cmdlet.
.EXAMPLE
	PS C:\> Get-DatastoreCluster |Invoke-SdrsRecommendation -Confirm:$false
.EXAMPLE
	PS C:\> Get-DatastoreCluster LAB |Invoke-SdrsRecommendation
.NOTES
	Author      :: Roman Gelman @rgelman75
	Shell       :: Tested on PowerShell 5.0 | PowerCLi 6.5.2
	Platform    :: Tested on vSphere 5.5 | VCenter 5.5U2
	Version 1.0 :: 30-Aug-2017 :: [Release] :: Publicly available
.LINK
	https://ps1code.com/2017/09/06/sdrs-powercli-part2
#>
	
	[CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
	[Alias("Invoke-ViMSdrsRecommendation")]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.DatastoreCluster]$DatastoreCluster
	)
	
	Begin
	{
		$ErrorActionPreference = 'Stop'
		$WarningPreference = 'SilentlyContinue'
		$storMgr = Get-View StorageResourceManager
	}
	Process
	{
		Try
		{
			if ($PSCmdlet.ShouldProcess("SDRS Cluster [$($DatastoreCluster.Name)]", "Run Storage DRS recommendations"))
			{
				$storMgr.RefreshStorageDrsRecommendation($DatastoreCluster.Id)
				[pscustomobject] @{
					DatastoreCluster = $DatastoreCluster.Name
					LastAction = $DatastoreCluster.ExtensionData.PodStorageDrsEntry.ActionHistory.Time.ToLocalTime() | sort -Descending | select -First 1
					Refreshed = Get-Date
				}
			}
		}
		Catch
		{
			"{0}" -f $Error.Exception.Message
		}
	}
	End { }
	
} #EndFunction Invoke-SdrsRecommendation
