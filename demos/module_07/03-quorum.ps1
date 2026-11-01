# ci: skip (Windows cluster of the course, not the containers)
# Runs on a node of the cluster. Module 7, clip 7.2: the quorum as it is configured (type,
# witness) and the votes as dynamic quorum distributes them at this moment. NodeWeight is the
# vote assigned to a node, DynamicWeight the vote it has now.
$ProgressPreference = 'SilentlyContinue'
"== Get-ClusterQuorum"
Get-ClusterQuorum | Format-List Cluster, QuorumResource, QuorumType
"== Get-Cluster"
Get-Cluster | Format-List Name, DynamicQuorum, WitnessDynamicWeight, LowerQuorumPriorityNodeID
"== Get-ClusterNode"
Get-ClusterNode | Format-Table Id, Name, State, NodeWeight, DynamicWeight -AutoSize
