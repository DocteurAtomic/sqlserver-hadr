-- Run by pacemaker.sh on each node, with PW set to the password of the login: the login the
-- resource agent ocf:mssql:ag connects with, and its permissions (Learn, "Create and configure
-- an availability group for SQL Server on Linux"). The group must exist on the instance.
SET NOCOUNT ON;
IF SUSER_ID(N'pacemakerLogin') IS NULL
    CREATE LOGIN pacemakerLogin WITH PASSWORD = N'$(PW)';
GRANT VIEW SERVER STATE TO pacemakerLogin;
GRANT ALTER, CONTROL, VIEW DEFINITION ON AVAILABILITY GROUP::AgPcs TO pacemakerLogin;
