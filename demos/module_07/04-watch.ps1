# ci: skip (Windows cluster of the course, not the containers)
# Runs on the node that must survive, while the other node is stopped or loses power.
# Module 7, clips 7.2 and 7.3: every half second, the cluster service, the nodes and their
# votes (State/NodeWeight/DynamicWeight), the owners of the roles, then what SQL Server sees:
# the quorum, the role of the local replica, the state of each copy of PachaDataFormation, and
# a read of the database. A line is printed only when something changes, with the time (UTC)
# the poll started and the time it ended: a cluster call can block for about twenty seconds
# while a node is lost.
# Usage: .\04-watch.ps1 -Seconds 150
param([int]$Seconds = 120)
$ProgressPreference = 'SilentlyContinue'
$end = (Get-Date).AddSeconds($Seconds)
$q = "SET NOCOUNT ON; SELECT CONCAT(ISNULL((SELECT quorum_state_desc FROM sys.dm_hadr_cluster), 'no-cluster-row'), ' ', (SELECT rs.role_desc + ' ' + rs.synchronization_health_desc FROM sys.dm_hadr_availability_replica_states rs WHERE rs.is_local = 1), ' ', (SELECT STRING_AGG(CONCAT(ar.replica_server_name, ':', d.synchronization_state_desc), ',') FROM sys.dm_hadr_database_replica_states d JOIN sys.availability_replicas ar ON ar.replica_id = d.replica_id WHERE d.database_id = DB_ID('PachaDataFormation'))); SELECT CONCAT('read:', COUNT(*)) FROM PachaDataFormation.sys.objects WHERE type = 'U';"
$last = ''
while ((Get-Date) -lt $end) {
    $t0 = (Get-Date).ToUniversalTime().ToString('HH:mm:ss.f')
    $svc = (Get-Service ClusSvc).Status
    $nodes = try { (Get-ClusterNode -ErrorAction Stop | ForEach-Object { "$($_.Name)=$($_.State)/$($_.NodeWeight)/$($_.DynamicWeight)" }) -join ' ' } catch { 'Get-ClusterNode: ' + $_.Exception.Message.Split("`n")[0] }
    $grp = try { (Get-ClusterGroup -ErrorAction Stop | Where-Object Name -in 'Pacha', 'Cluster Group' | ForEach-Object { "$($_.Name)@$($_.OwnerNode)=$($_.State)" }) -join ' ' } catch { '-' }
    $s = (sqlcmd -S . -E -C -h -1 -W -l 3 -t 3 -Q $q 2>&1 | Out-String).Trim() -replace '\s+', ' ' -replace 'Msg (\d+),.*', 'Msg $1'
    $line = "clussvc=$svc | $nodes | $grp | sql: $s"
    $t = (Get-Date).ToUniversalTime().ToString('HH:mm:ss.f')
    if ($line -ne $last) { "$t0-$t $line"; $last = $line }
    Start-Sleep -Milliseconds 500
}
