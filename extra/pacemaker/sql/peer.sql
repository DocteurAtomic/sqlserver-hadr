-- Run by endpoints.sh on each node, once per other node P: the certificate of P opens the
-- local endpoint to P. Running it again changes nothing.
USE master;
SET NOCOUNT ON;
IF SUSER_ID(N'$(P)_login') IS NULL
    CREATE LOGIN $(P)_login WITH PASSWORD = N'Hadr-2026!peer$(P)';
IF USER_ID(N'$(P)_user') IS NULL
    CREATE USER $(P)_user FOR LOGIN $(P)_login;
IF CERT_ID(N'$(P)_cert') IS NULL
    CREATE CERTIFICATE $(P)_cert AUTHORIZATION $(P)_user
        FROM FILE = N'/var/opt/mssql/data/$(P)_cert.cer';
GRANT CONNECT ON ENDPOINT::hadr_endpoint TO $(P)_login;
