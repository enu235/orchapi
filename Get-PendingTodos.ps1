#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$Disconnect,
    [switch]$Raw,
    [switch]$Json
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
$select     = 'id,title,body,dueDateTime,importance,status,lastModifiedDateTime'

foreach ($list in $lists) {
    $uri = "https://graph.microsoft.com/v1.0/me/todo/lists/$($list.id)/tasks?`$filter=$encoded&`$top=100&`$select=$select"
    try   { $tasks = Invoke-PagedRequest -Uri $uri }
    catch { Write-Warning "List '$($list.displayName)': $_"; continue }

    if (-not $tasks -or $tasks.Count -eq 0) { continue }
    $totalCount += $tasks.Count

    $rows = $tasks | ForEach-Object {
        $task = $_
        $dueFormatted = Format-Due $task.dueDateTime
        [pscustomobject]@{
            id           = $task.id
            listId       = $list.id
            listName     = $list.displayName
            title        = $task.title
            body         = if ($task.body) { $task.body.content } else { '' }
            due          = if ($task.dueDateTime) { $task.dueDateTime.dateTime } else { $null }
            importance   = $task.importance
            status       = $task.status
            etag         = $task.'@odata.etag'
            lastModified = $task.lastModifiedDateTime
            _due         = $dueFormatted   # formatted; used for display/sort only
        }
    } | Sort-Object { if ($_._due -eq '—') { '9999-99-99' } else { $_._due } }

    $rawItems += $rows

    if (-not ($Raw -or $Json)) {
        Write-Host ''
        Write-Host "  $($list.displayName)  ($($tasks.Count) pending)" -ForegroundColor Cyan
        Write-Host ("  " + '─' * 60) -ForegroundColor DarkGray
        $rows | Format-Table @{n='Title';e={$_.title}}, @{n='Due';e={$_._due}},
            @{n='Importance';e={$_.importance}}, @{n='Status';e={$_.status}} -AutoSize
    }
}

if ($Json) {
    $rawItems | Select-Object id, listId, listName, title, body, due, importance, status, etag, lastModified |
        ConvertTo-Json -Depth 5
} elseif ($Raw) {
    $rawItems | Select-Object id, listId, listName, title, body, due, importance, status, etag, lastModified
} else {
    Write-Host ''
    Write-Host "  Total pending: $totalCount" -ForegroundColor Green
}

if ($Disconnect) {
    Disconnect-MgGraph | Out-Null
    Write-Host '  Disconnected from Microsoft Graph.' -ForegroundColor DarkGray
}
