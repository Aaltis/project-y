# PROBLEM

database init scripts are not run or they hang whole run
# keycloak

## dashboard

to imitate run 
''minikube tunnel''

get external ip from
kubectl get svc keycloak

login 
http://<external-ip>:8090/


---

#port forwarding for keycloak

kubectl port-forward svc/keycloak 8090:8080
-> [locahlost:8090](http://localhost:8090)
---

### Minikube start with extra resources and add ingress:

minikube start --memory=8192 --cpus=4

minikube addons enable ingress

### install
helm install project-y ./deployment -f ./deployment/values-dev.yaml
helm upgrade --install project-y /deployment -f ./deployment/values-dev.yaml --force
### check template:
helm template project-y ./deployment -f ./deployment/values-dev.yaml --debug

## uninstall

helm uninstall project-y

---

### push docker image
docker tag customer:latest aaltis/customer:latest
docker login
docker push aaltis/customer:latest

###
docker run -d -p 5000:5000 --restart=always --name local-registry registry:2
docker tag customer:latest localhost:5000/customer:latest
docker push localhost:5000/customer:latest
curl http://localhost:5000/v2/_catalog
minikube addons enable registry
docker tag customer:latest localhost:5000/customer


### debug:
kubectl logs -f customer-648889d95b-tmjtq


 kubectl logs -l app=postgres-keycloak -f