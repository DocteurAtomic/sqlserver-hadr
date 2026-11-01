# ci: skip (Windows cluster of the course, not the containers)
# Runs on a node of the cluster. Module 8, clip 8.3: the same failover policy, read as private
# properties of the cluster resource Pacha (LeaseTimeout lives only there), and the restart
# and failover policy of the resource and of the role.
# Usage: .\06-lease.ps1
$ProgressPreference = 'SilentlyContinue'
'== Get-ClusterParameter, resource Pacha'
Get-ClusterResource Pacha | Get-ClusterParameter LeaseTimeout, HealthCheckTimeout, FailureConditionLevel |
    Format-Table Name, Value -AutoSize
'== Restart policy of the resource'
Get-ClusterResource Pacha | Format-List RestartAction, RestartThreshold, RestartPeriod, RetryPeriodOnFailure
'== Failover policy of the role'
Get-ClusterGroup Pacha | Format-List FailoverThreshold, FailoverPeriod, AutoFailbackType
