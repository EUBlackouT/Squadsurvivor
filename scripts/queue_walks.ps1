Param(
    [Parameter(Mandatory = $false)]
    [String] $Token = $env:PIXELLAB_TOKEN,

    [Parameter(Mandatory = $false)]
    [Int] $DelaySeconds = 3
)

if (-not $Token -or $Token.Trim().Length -eq 0) {
    Write-Error "PixelLab token not provided. Set PIXELLAB_TOKEN env var or pass -Token."
    exit 1
}

$Endpoint = "https://api.pixellab.ai/mcp"
$Characters = @(
    # Humanoids
    "f1ec653e-8d03-4735-aadd-c6de03c67129", # Skeleton Warrior
    "986b7bae-27ab-4d42-805e-762baf05ce3d", # Dark Mage
    "53966bad-056b-459a-8c2b-68c55a19808b", # Steam Knight
    "42df64d0-8d98-4c7f-b8e4-d8225b29e16b", # Fire Demon
    "c03b89bf-f710-4982-a889-a2e860cca58f", # Ice Elemental
    "42deaa0b-9b34-445d-abe4-d27390445c51", # Shadow Rogue
    "44a2e413-20b3-49e3-8da2-e5fcf6af8240", # Holy Paladin
    "aa1c3217-73a8-47ed-92e6-ab21cf012027", # Zombie
    "8757a74f-1ed0-4400-b2db-34a90c15d113", # Goblin Warrior
    "3e9b116b-2992-4070-927e-f7f996bf5a82"  # Necromancer
)

$Headers = @{
    "Content-Type"  = "application/json"
    "Accept"        = "application/json, text/event-stream"
    "Authorization" = "Bearer $Token"
}

function Queue-Walk {
    param(
        [string] $CharacterId
    )

    $Body = @{
        jsonrpc = "2.0"
        id      = [Guid]::NewGuid().ToString()
        method  = "animate_character"
        params  = @{
            character_id          = $CharacterId
            template_animation_id = "walking-8-frames"
            action_description    = "walking loop"
            animation_name        = "walk"
        }
    } | ConvertTo-Json -Depth 5

    try {
        $resp = Invoke-RestMethod -Method Post -Uri $Endpoint -Headers $Headers -Body $Body
        Write-Host "Queued walk for $CharacterId -> result: $($resp.result | ConvertTo-Json -Depth 5)" -ForegroundColor Green
    }
    catch {
        Write-Warning ("Failed for {0}: {1}" -f $CharacterId, $_.Exception.Message)
        if ($_.ErrorDetails) { Write-Warning $_.ErrorDetails }
    }
}

foreach ($cid in $Characters) {
    Queue-Walk -CharacterId $cid
    Start-Sleep -Seconds $DelaySeconds
}

Write-Host "Done queuing walking animations." -ForegroundColor Cyan

