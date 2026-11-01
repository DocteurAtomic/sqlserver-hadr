#!/usr/bin/env bash
# Clip 3.1: what setup/install.sh created for the availability groups, read on the three
# instances, without changing anything. On each one: the endpoint (port, role, certificate
# authentication, AES encryption), the certificates of master (its own, with a private key
# protected by the database master key, and those of the two others, public part only), the
# logins that own them and their CONNECT permission on the endpoint. Then the files of the
# shared volume through which the certificates went. Run after 00-setup.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
for n in $nodes; do
    echo "== $n"
    sql $n -s '|' <<'SQL'
SET NOCOUNT ON;
SELECT e.name AS endpoint, t.port, e.state_desc AS state, e.role_desc AS role,
       e.connection_auth_desc AS authentication, c.name AS certificate,
       e.encryption_algorithm_desc AS encryption
FROM sys.database_mirroring_endpoints AS e
JOIN sys.tcp_endpoints AS t ON t.endpoint_id = e.endpoint_id
LEFT JOIN sys.certificates AS c ON c.certificate_id = e.certificate_id;
SELECT c.name AS certificate, c.pvt_key_encryption_type_desc AS private_key,
       CONVERT(char(10), c.expiry_date, 120) AS expires, p.name AS owner,
       IIF(EXISTS (SELECT * FROM sys.server_permissions AS sp
                   JOIN sys.server_principals AS l ON l.principal_id = sp.grantee_principal_id
                   WHERE sp.class_desc = N'ENDPOINT' AND sp.permission_name = N'CONNECT'
                     AND sp.state = N'G' AND l.sid = p.sid), N'CONNECT', N'') AS on_endpoint
FROM master.sys.certificates AS c
JOIN master.sys.database_principals AS p ON p.principal_id = c.principal_id
WHERE c.name LIKE N'hadrlab%[_]cert'
ORDER BY c.name;
SQL
done
echo
echo "The public parts on the shared volume:"
$engine exec hadrlab1 ls -l /var/opt/mssql/share/certs
