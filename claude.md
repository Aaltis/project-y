# Minikube Node Access Debugging

## Problem
Cannot make calls to Kubernetes nodes without running `minikube tunnel`.

## Root Cause Context

Minikube runs the cluster inside a VM or container. Node IPs (e.g. `192.168.49.x`) are internal to Minikube's network and not routable from the host by default. Services of type `LoadBalancer` get stuck in `<pending>` state without a tunnel.

---

## Step-by-Step Debugging

### 1. Confirm the cluster is running

```bash
minikube status
kubectl get nodes
```

Expected: node should be in `Ready` state.

### 2. Check the Minikube IP

```bash
minikube ip
```

This is the gateway IP you use instead of `localhost`. Try pinging it from your host.

### 3. Identify what type of Service you are hitting

```bash
kubectl get svc -A
```

- `ClusterIP` — only reachable inside the cluster. Use `kubectl port-forward` or `kubectl proxy`.
- `NodePort` — reachable at `$(minikube ip):<nodePort>`.
- `LoadBalancer` — requires `minikube tunnel` OR use `minikube service <name>` instead.

### 4. Use the correct access method per service type

**NodePort (no tunnel needed):**
```bash
minikube service <service-name> --url
# or manually:
curl http://$(minikube ip):<nodePort>
```

**LoadBalancer (alternative to tunnel):**
```bash
minikube service <service-name>
# opens the URL automatically, or use --url to just print it
```

**ClusterIP (port-forward):**
```bash
kubectl port-forward svc/<service-name> 8080:<service-port>
curl http://localhost:8080
```

### 5. If you need `minikube tunnel` — run it correctly

`minikube tunnel` requires elevated privileges and must stay running in a separate terminal:

```bash
# In a separate terminal (may prompt for sudo/admin)
minikube tunnel
```

Then check the service gets an external IP:
```bash
kubectl get svc <service-name>
# EXTERNAL-IP should no longer be <pending>
```

### 6. Check network driver (common cause)

The default driver affects networking. List current driver:
```bash
minikube profile list
```

Drivers and their node-access behavior:
- `docker` — node IP not directly routable on Windows/Mac; use `minikube service` or tunnel
- `hyperv` / `virtualbox` — node IP is usually routable from host
- `none` (bare metal Linux) — full direct access, no tunnel needed

To switch driver:
```bash
minikube delete
minikube start --driver=hyperv   # or virtualbox, docker, etc.
```

### 7. OpenShift-specific: check Routes vs Services

If you are using OpenShift APIs on top of Minikube, Routes may not resolve. Verify:
```bash
kubectl get routes -A     # or oc get routes -A
```

For OpenShift routes to work locally, add the route hostname to your `/etc/hosts`:
```
$(minikube ip)  <route-hostname>
```

### 8. Inspect pod-to-pod and pod-to-service connectivity

```bash
# Check DNS inside cluster
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Check connectivity from inside a pod
kubectl exec -it <pod-name> -- curl http://<service-name>:<port>
```

### 9. Check firewall / antivirus on Windows

Windows Defender or third-party firewalls can block Minikube's virtual network adapter. Ensure the `vEthernet (minikube)` or equivalent adapter is on a trusted network profile.

---

## Quick Reference: Access Methods

| Service Type  | Best Access Method                          |
|---------------|---------------------------------------------|
| ClusterIP     | `kubectl port-forward`                      |
| NodePort      | `minikube ip` + node port                   |
| LoadBalancer  | `minikube tunnel` OR `minikube service`     |
| OpenShift Route | `/etc/hosts` entry pointing to minikube ip |
