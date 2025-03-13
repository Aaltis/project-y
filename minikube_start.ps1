minikube start --memory=4096 --cpus=2 --disk-size=20g
minikube addons enable ingress
# Enable the default storage class in Minikube.
# --------------------------------------------------
# Minikube does not always automatically provision a default storage class,
# which can cause PersistentVolumeClaims (PVCs) to remain in a "Pending" state.
# Enabling this addon ensures that Kubernetes can dynamically create PersistentVolumes (PVs)
# for storage requests made by PostgreSQL, Keycloak, and other services.
# Without this, pods requiring persistent storage may fail to start.
# --------------------------------------------------
minikube addons enable default-storageclass

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
# Start Minikube Tunnel in a New PowerShell Window
Start-Process powershell -ArgumentList "-NoExit", "-Command minikube tunnel"

# Start Minikube Dashboard in Another PowerShell Window
Start-Process powershell -ArgumentList "-NoExit", "-Command minikube dashboard"

Write-Host "✅ Minikube Tunnel & Dashboard started in separate windows!" -ForegroundColor Green
