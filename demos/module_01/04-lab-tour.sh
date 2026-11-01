#!/usr/bin/env bash
# Clip 1.3: the lab. The three containers, what each instance is, the shared volume seen
# from the three, and what the lab does not have: no cluster under the instances (the
# cluster views answer with a cluster without a name, whose only member is the instance).
# Run after 00-setup.sh (it reads its backup files on the shared volume).
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
$engine ps --filter name=hadrlab --format '{{.Names}}  {{.Status}}  {{.Ports}}'
echo
for n in $nodes; do
    sql $n -h -1 -s '|' <<'SQL'
SET NOCOUNT ON;
SELECT @@SERVERNAME,
       CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(20)),
       CAST(SERVERPROPERTY('ProductUpdateLevel') AS nvarchar(10)),
       CONCAT((SELECT physical_memory_kb / 1024 FROM sys.dm_os_sys_info), ' MB seen'),
       CONCAT('hadr ', CAST(SERVERPROPERTY('IsHadrEnabled') AS int)),
       CONCAT('clustered ', CAST(SERVERPROPERTY('IsClustered') AS int)),
       CONCAT('cluster name ''', (SELECT cluster_name FROM sys.dm_hadr_cluster), ''''),
       CONCAT('cluster members ', (SELECT STRING_AGG(member_name, ',') FROM sys.dm_hadr_cluster_members)),
       CONCAT('endpoint ', (SELECT CONCAT(state_desc, ' ', connection_auth_desc)
                            FROM sys.database_mirroring_endpoints));
SQL
done
echo
echo "The shared volume, from hadrlab3:"
$engine exec hadrlab3 ls -l /var/opt/mssql/share /var/opt/mssql/share/m01
echo
echo "A backup written by hadrlab1, checked by hadrlab3:"
sql hadrlab3 -Q "RESTORE VERIFYONLY FROM DISK = N'/var/opt/mssql/share/m01/m01_registration_log3.trn';"
