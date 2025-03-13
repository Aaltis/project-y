# Get the Keycloak Postgres pod name
$pgPod = kubectl get pod -l app=postgres-keycloak -o jsonpath="{.items[0].metadata.name}"

if (-not $pgPod) {
    Write-Host "❌ No Keycloak Postgres pod found."
    exit 1
}

Write-Host "✅ Found Postgres pod: $pgPod"

# Run the psql command inside the pod to list databases
$databaseCheck = kubectl exec -it $pgPod -- psql -U keycloak -c "SELECT datname FROM pg_database;"

if ($databaseCheck -match "keycloak") {
    Write-Host "✅ Keycloak database exists!"
} else {
    Write-Host "❌ Keycloak database NOT found!"
    Write-Host "ℹ️  You might need to manually create it:"
    Write-Host "kubectl exec -it $pgPod -- psql -U keycloak -c `"CREATE DATABASE keycloak;`""
}
 kubectl exec -it postgres-keycloak-75794785cb-bnrf2 -- psql -U keycloak -c "SELECT datname FROM pg_database;"