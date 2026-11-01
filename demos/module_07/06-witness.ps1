# ci: skip (Windows cluster of the course, not the containers)
# Module 7, clip 7.3: a file share witness on DC01 (Windows name DC), the domain controller
# of the lab, which is not a node; then the same power loss of SQL02 as before. The share
# gives full control to the cluster computer account (PACHADATA\cluster$). In production, the
# witness goes on a server of its own, outside the rooms of the nodes; a domain controller is
# a lab shortcut. -Remove puts the cluster back without a witness and deletes the share.
# Measured on the course cluster: setting the witness raises QuorumArbitrationTimeMax from 20
# to 90 seconds, and -NoWitness leaves it at 90; -Cluster -Remove sets it back to
# -ArbitrationTimeMax (20, the value read before the witness).
# Usage, on DC01:  .\06-witness.ps1 -Share          (-Share -Remove to delete it)
#        on SQL01: .\06-witness.ps1 -Cluster        (-Cluster -Remove to go back to no witness)
param([switch]$Share, [switch]$Cluster, [switch]$Remove, [int]$ArbitrationTimeMax = 20)
$ProgressPreference = 'SilentlyContinue'
if ($Share -and -not $Remove) {
    New-Item -ItemType Directory -Force C:\m07-fsw | Out-Null
    $acl = Get-Acl C:\m07-fsw
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule('PACHADATA\cluster$', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    Set-Acl C:\m07-fsw $acl
    New-SmbShare -Name m07-fsw -Path C:\m07-fsw -FullAccess 'PACHADATA\cluster$', 'PACHADATA\Administrator' | Format-List Name, Path
}
if ($Share -and $Remove) {
    Remove-SmbShare -Name m07-fsw -Force
    Remove-Item C:\m07-fsw -Recurse -Force
}
if ($Cluster -and -not $Remove) {
    Set-ClusterQuorum -FileShareWitness \\DC\m07-fsw | Format-List Cluster, QuorumResource, QuorumType
}
if ($Cluster -and $Remove) {
    Set-ClusterQuorum -NoWitness | Format-List Cluster, QuorumResource, QuorumType
    (Get-Cluster).QuorumArbitrationTimeMax = $ArbitrationTimeMax
}
if ($Cluster) {
    Get-Cluster | Format-List DynamicQuorum, WitnessDynamicWeight, QuorumArbitrationTimeMax
    Get-ClusterNode | Format-Table Id, Name, State, NodeWeight, DynamicWeight -AutoSize
}
