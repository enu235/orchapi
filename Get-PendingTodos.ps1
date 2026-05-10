#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$Disconnect,
    [switch]$Raw
)

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-Host 'Installing Microsoft.Graph.Authentication (current user)...' -ForegroundColor Cyan
    Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber
}
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

Connect-MgGraph -Scopes 'Tasks.Read' -NoWelcome

function Invoke-PagedRequest {
    param([string]$Uri)
    $items = @()
    do {
        $page = Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType PSObject
        if ($page.value) { $items += $page.value }
        $Uri = $page.'@odata.nextLink'
    } while ($Uri)
    return ,$items
}

function Format-Due {
    param($due)
    if (-not $due -or -not $due.dateTime) { return '—' }
    try {
        [datetime]::Parse($due.dateTime, $null,
            [System.Globalization.DateTimeStyles]::AssumeUniversal
        ).ToLocalTime().ToString('yyyy-MM-dd')
    } catch { '—' }
}

try {
    $lists = Invoke-PagedRequest -Uri 'https://graph.microsoft.com/v1.0/me/todo/lists?$top=100'
} catch {
    Write-Error "Failed to retrieve To Do lists: $_"; exit 1
}

$totalCount = 0
$rawItems   = @()
$encoded    = [Uri]::EscapeDataString("status ne 'completed'")

foreach ($list in $lists) {
    $uri = "https://graph.microsoft.com/v1.0/me/todo/lists/$($list.id)/tasks?`$filter=$encoded&`$top=100"
    try   { $tasks = Invoke-PagedRequest -Uri $uri }
    catch { Write-Warning "List '$($list.displayName)': $_"; continue }

    if (-not $tasks -or $tasks.Count -eq 0) { continue }
    $totalCount += $tasks.Count

    $rows = $tasks | ForEach-Object {
        [pscustomobject]@{
            ListName   = $list.displayName
            Title      = $_.title
            Due        = Format-Due $_.dueDateTime
            Importance = $_.importance
            Status     = $_.status
        }
    } | Sort-Object { if ($_.Due -eq '—') { '9999-99-99' } else { $_.Due } }

    if ($Raw) {
        $rawItems += $rows
    } else {
        Write-Host ''
        Write-Host "  $($list.displayName)  ($($tasks.Count) pending)" -ForegroundColor Cyan
        Write-Host ("  " + '─' * 60) -ForegroundColor DarkGray
        $rows | Format-Table Title, Due, Importance, Status -AutoSize
    }
}

if ($Raw) {
    $rawItems
} else {
    Write-Host ''
    Write-Host "  Total pending: $totalCount" -ForegroundColor Green
}

if ($Disconnect) {
    Disconnect-MgGraph | Out-Null
    Write-Host '  Disconnected from Microsoft Graph.' -ForegroundColor DarkGray
}
