# ci: skip (Windows cluster of the course, not the containers)
# Runs on a machine that is not a node of the cluster (DC01 in the videos), in a PowerShell
# session of a domain user who can write into the database. Module 8, clips 8.1 and 8.2, and
# module 10, clip 10.4 (-Database m10_rolling):
# the application seen from outside. Every half second, a new connection to the listener
# (no pooling, so that every attempt resolves the name and connects again), one INSERT, and
# the name of the instance that answered. A line is printed only when the answer changes,
# with the UTC time; the end gives the attempts, the failures and the longest time without a
# successful INSERT.
# Usage: .\02-client.ps1 -Seconds 120 [-Server PachaSQL] [-MultiSubnetFailover $true] [-Database m08_registrations]
param([int]$Seconds = 120, [string]$Server = 'PachaSQL', [bool]$MultiSubnetFailover = $true,
      [string]$Database = 'm08_registrations')
$cs = "Server=tcp:$Server,1433;Database=$Database;Integrated Security=SSPI;" +
      "MultiSubnetFailover=$MultiSubnetFailover;Pooling=False;Connect Timeout=5"
$end = (Get-Date).AddSeconds($Seconds)
$seq = 0; $failed = 0; $last = ''; $lastOk = $null; $gap = [TimeSpan]::Zero; $gapFrom = $null
while ((Get-Date) -lt $end) {
    $seq++
    $t = (Get-Date).ToUniversalTime()
    try {
        $cn = New-Object System.Data.SqlClient.SqlConnection $cs
        $cn.Open()
        $cmd = $cn.CreateCommand()
        $cmd.CommandTimeout = 5
        $cmd.CommandText = "INSERT dbo.attempts (client_seq, client_time) VALUES ($seq, '$($t.ToString('yyyy-MM-dd HH:mm:ss.f'))'); SELECT @@SERVERNAME;"
        $answer = "ok on $($cmd.ExecuteScalar())"
        $cn.Close()
        if ($lastOk -and ($t - $lastOk) -gt $gap) { $gap = $t - $lastOk; $gapFrom = $lastOk }
        $lastOk = $t
    } catch {
        $failed++
        $answer = 'error: ' + ($_.Exception.InnerException, $_.Exception -ne $null)[0].Message.Split("`n")[0]
    }
    $took = ((Get-Date).ToUniversalTime() - $t).TotalSeconds
    if ($answer -ne $last) { '{0} #{1} {2} ({3:0.0} s)' -f $t.ToString('HH:mm:ss.f'), $seq, $answer, $took; $last = $answer }
    Start-Sleep -Milliseconds 500
}
'{0} end: {1} attempts, {2} failed, longest time between two successful INSERTs {3:0.0} s (from {4})' -f `
    (Get-Date).ToUniversalTime().ToString('HH:mm:ss.f'), $seq, $failed, $gap.TotalSeconds, $(if ($gapFrom) { $gapFrom.ToString('HH:mm:ss.f') } else { '-' })
