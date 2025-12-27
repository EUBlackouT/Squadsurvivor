Param(
    [Parameter(Mandatory = $true)]
    [String] $Token
)

$ErrorActionPreference = "Stop"

$Endpoint = "https://api.pixellab.ai/mcp"
$Headers = @{
    "Content-Type"  = "application/json"
    "Accept"        = "application/json"
    "Authorization" = "Bearer $Token"
}

$Body = @{
    jsonrpc = "2.0"
    id      = "1"
    method  = "list_characters"
    params  = @{
        limit  = 5
        offset = 0
    }
} | ConvertTo-Json -Depth 6

$resp = Invoke-RestMethod -Method Post -Uri $Endpoint -Headers $Headers -Body $Body
$resp | ConvertTo-Json -Depth 10


