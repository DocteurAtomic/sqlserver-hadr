-- Run by install.sh on each instance, with the variable N set to the instance name.
-- Database master key, a certificate for the instance, the endpoint authenticated by that
-- certificate, and the public part of the certificate written to the shared volume for the
-- other instances. Lab passwords, written in clear: never reuse them elsewhere.
-- Running it again changes nothing that already exists.
USE master;
SET NOCOUNT ON;
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Hadr-2026!masterkey';
IF CERT_ID(N'$(N)_cert') IS NULL
    CREATE CERTIFICATE $(N)_cert WITH SUBJECT = N'HADR endpoint of $(N)', EXPIRY_DATE = '20361231';
GO
BACKUP CERTIFICATE $(N)_cert TO FILE = N'/var/opt/mssql/share/certs/$(N)_cert.cer';
GO
IF NOT EXISTS (SELECT * FROM sys.endpoints WHERE type_desc = N'DATABASE_MIRRORING')
    CREATE ENDPOINT hadr_endpoint
        STATE = STARTED
        AS TCP (LISTENER_PORT = 5022)
        FOR DATABASE_MIRRORING (
            ROLE = ALL,
            AUTHENTICATION = CERTIFICATE $(N)_cert,
            ENCRYPTION = REQUIRED ALGORITHM AES);
