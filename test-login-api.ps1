$headers = @{
    "Content-Type" = "application/json"
}

$body = @{
    username = "admin"
    password = "password"
    grant_type = "password"
    client_id = "my-client"
    client_secret = "my-secret"
} | ConvertTo-Json -Depth 10

$response = Invoke-RestMethod -Uri "http://localhost/auth/realms/test/protocol/openid-connect/token" `
    -Method Post `
    -Headers $headers `
    -Body $body

Write-Output $response
