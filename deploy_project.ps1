# Define variables
$RELEASE_NAME = "project-y"
$DEPLOYMENT_PATH = "./deployment"
$VALUES_FILE = "./deployment/values-dev.yaml"

# Check if the Helm release exists
$releaseExists = helm list -q | Select-String -Pattern "^$RELEASE_NAME$"

if ($releaseExists) {
    Write-Host "🛑 Found existing Helm release '$RELEASE_NAME'. Uninstalling..."
    helm uninstall $RELEASE_NAME --debug
    Start-Sleep -Seconds 5
} else {
    Write-Host "✅ No existing Helm release '$RELEASE_NAME' found. Skipping uninstall."
}

Write-Host "🚀 Installing Helm release: $RELEASE_NAME..."
helm install $RELEASE_NAME $DEPLOYMENT_PATH -f $VALUES_FILE --debug

Write-Host "✅ Deployment process completed!"
