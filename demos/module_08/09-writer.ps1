# ci: skip (Windows cluster of the course, not the containers)
# Runs on the primary replica (SQL01). Module 8, clip 8.4: one INSERT every half second into
# m08_registrations, each with its number, through a new local connection, so that a session
# killed by SQL Server does not stop the loop. A line is printed for every INSERT that fails
# or takes more than one second, then the numbers that are in the table.
# Usage: .\09-writer.ps1 -Seconds 60 -Run 1
param([int]$Seconds = 60, [int]$Run = 1)
$ProgressPreference = 'SilentlyContinue'
$cs = 'Server=.;Database=m08_registrations;Integrated Security=SSPI;Pooling=False;Connect Timeout=5'
$end = (Get-Date).AddSeconds($Seconds); $seq = $Run * 1000
while ((Get-Date) -lt $end) {
    $seq++; $t = (Get-Date).ToUniversalTime()
    try {
        $cn = New-Object System.Data.SqlClient.SqlConnection $cs; $cn.Open()
        $cmd = $cn.CreateCommand(); $cmd.CommandTimeout = 60
        $cmd.CommandText = "INSERT dbo.attempts (client_seq, client_time) VALUES ($seq, SYSUTCDATETIME());"
        [void]$cmd.ExecuteNonQuery(); $cn.Close(); $answer = 'ok'
    } catch {
        $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }
        $nums = if ($e.Errors) { ($e.Errors | ForEach-Object { "Msg $($_.Number)" }) -join ', ' } else { '' }
        $answer = "error $nums : " + $e.Message.Split("`n")[0]
    }
    $took = ((Get-Date).ToUniversalTime() - $t).TotalSeconds
    if ($answer -ne 'ok' -or $took -gt 1) { '{0} #{1} {2} ({3:0.0} s)' -f $t.ToString('HH:mm:ss.f'), $seq, $answer, $took }
    Start-Sleep -Milliseconds 500
}
'== rows of run {0} in the table: {1}' -f $Run, (sqlcmd -S . -E -C -h -1 -W -Q "SET NOCOUNT ON; SELECT CONCAT(COUNT(*), ' rows, numbers ', MIN(client_seq), ' to ', MAX(client_seq)) FROM m08_registrations.dbo.attempts WHERE client_seq BETWEEN $($Run * 1000) AND $($Run * 1000 + 999)")
