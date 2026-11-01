-- Run by test-lab.sh on each instance, with the variable N set to the instance name.
-- One row per check: the check, then 1 when it holds and 0 when it does not.
SET NOCOUNT ON;
DECLARE @c TABLE (n int IDENTITY, chk nvarchar(200), ok bit);
INSERT @c SELECT N'server name is $(N)', IIF(@@SERVERNAME = N'$(N)', 1, 0);
INSERT @c SELECT N'SQL Server 2025 (17.x)', IIF(CAST(SERVERPROPERTY('ProductMajorVersion') AS int) = 17, 1, 0);
INSERT @c SELECT N'HADR enabled', IIF(SERVERPROPERTY('IsHadrEnabled') = 1, 1, 0);
INSERT @c SELECT N'SQL Server Agent running',
    IIF(EXISTS (SELECT * FROM sys.dm_exec_sessions WHERE program_name LIKE N'SQLAgent%'), 1, 0);
INSERT @c SELECT N'memory seen by the instance at most 2 GB',
    IIF((SELECT physical_memory_kb FROM sys.dm_os_sys_info) <= 2 * 1024 * 1024, 1, 0);
INSERT @c SELECT N'endpoint started on port 5022, certificate authentication',
    IIF(EXISTS (SELECT * FROM sys.database_mirroring_endpoints e
                JOIN sys.tcp_endpoints t ON t.endpoint_id = e.endpoint_id
                WHERE e.state_desc = N'STARTED' AND t.port = 5022
                  AND e.connection_auth_desc = N'CERTIFICATE'), 1, 0);
INSERT @c SELECT N'certificates of the two other instances, CONNECT granted',
    IIF((SELECT COUNT(*) FROM sys.server_permissions sp
         JOIN sys.server_principals p ON p.principal_id = sp.grantee_principal_id
         JOIN sys.certificates c ON c.name = REPLACE(p.name, N'_login', N'_cert')
         WHERE sp.class_desc = N'ENDPOINT' AND sp.permission_name = N'CONNECT'
           AND sp.state = N'G' AND p.name LIKE N'hadrlab%[_]login' AND p.name <> N'$(N)_login') = 2, 1, 0);
IF @@SERVERNAME = N'hadrlab1'
BEGIN
    INSERT @c SELECT N'PachadataTraining online, full recovery model',
        IIF(EXISTS (SELECT * FROM sys.databases WHERE name = N'PachadataTraining'
                    AND state_desc = N'ONLINE' AND recovery_model_desc = N'FULL'), 1, 0);
    INSERT @c SELECT N'PachadataTraining log chain started (full backup taken)',
        IIF((SELECT last_log_backup_lsn FROM sys.database_recovery_status
             WHERE database_id = DB_ID(N'PachadataTraining')) IS NOT NULL, 1, 0);
END;
SELECT CONCAT(IIF(ok = 1, N'ok   ', N'FAIL '), N'$(N): ', chk) FROM @c ORDER BY n;
