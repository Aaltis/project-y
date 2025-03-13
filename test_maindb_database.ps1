# Define Kubernetes pod and database details
$POSTGRES_POD = kubectl get pods -l app=postgres -o jsonpath="{.items[0].metadata.name}"
$POSTGRES_USER = "postgres"  # Change if different
$POSTGRES_PASSWORD = "postgres"  # Change if stored in secrets, load dynamically if needed
$DATABASE_NAME = "maindb"

# Execute PostgreSQL command inside the Kubernetes pod
$COMMAND = "PGPASSWORD=$POSTGRES_PASSWORD psql -U $POSTGRES_USER -d postgres -tc `"SELECT 1 FROM pg_database WHERE datname = '$DATABASE_NAME';`""

# Run the command inside the Kubernetes pod
$RESULT = kubectl exec -it $POSTGRES_POD -- sh -c $COMMAND

# Check the output to determine if the database exists
if ($RESULT -match "1") {
    Write-Host "✅ Database '$DATABASE_NAME' exists in PostgreSQL."
} else {
    Write-Host "❌ Database '$DATABASE_NAME' does NOT exist in PostgreSQL."
}