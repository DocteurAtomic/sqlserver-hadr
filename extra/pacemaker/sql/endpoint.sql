-- Run by endpoints.sh on each node, with N set to the node name and ROLE to ALL (pc1, pc2) or
-- WITNESS (pc3: the Express edition only accepts ROLE = WITNESS, Msg 7878 otherwise).
-- Database master key, a certificate for the node, the endpoint authenticated by it, and the
-- public part of the certificate written for the other nodes. Lab passwords, never reuse them.
USE master;
SET NOCOUNT ON;
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Hadr-2026!masterkey';
IF CERT_ID(N'$(N)_cert') IS NULL
    CREATE CERTIFICATE $(N)_cert WITH SUBJECT = N'HADR endpoint of $(N)', EXPIRY_DATE = '20361231';
GO
BACKUP CERTIFICATE $(N)_cert TO FILE = N'/var/opt/mssql/data/$(N)_cert.cer';
GO
IF NOT EXISTS (SELECT * FROM sys.endpoints WHERE type_desc = N'DATABASE_MIRRORING')
    CREATE ENDPOINT hadr_endpoint
        STATE = STARTED
        AS TCP (LISTENER_PORT = 5022)
        FOR DATABASE_MIRRORING (
            ROLE = $(ROLE),
            AUTHENTICATION = CERTIFICATE $(N)_cert,
            ENCRYPTION = REQUIRED ALGORITHM AES);
