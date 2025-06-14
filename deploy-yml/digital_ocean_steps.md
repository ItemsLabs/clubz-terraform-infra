Install locally `helm` and `doctl` and auth (https://docs.digitalocean.com/reference/doctl/how-to/install/)


# digital ocean ui
create kubernetes cluster 
create registry, attach it to the kubernetes cluster
create postgresql db, add k8s cluster as trusted source
connect to postgresql, give permissions to user

# rabbitmq
install rabbitmq kubernetes operator (https://www.rabbitmq.com/kubernetes/operator/install-operator.html)
```
kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml"
```

create rabbimtq cluster (https://www.rabbitmq.com/kubernetes/operator/using-operator.html)
```
kubectl apply -f ./k8s/030-rabbitmq-cluster.yaml
```

connect to management panel using port-forward - 15672 then http://localhost:15672/   # you need to retrieve the password and username with this command
# Retrieve the password
kubectl get secret rabbitmq-cluster -n rabbitmq-system -o jsonpath='{.data.rabbitmq-password}' | base64 --decode && echo

# Retrieve the username
"user"

kubectl port-forward service/rabbitmq-cluster 15672:15672 -n rabbitmq-system
create vhost `ufl` in the management panel. 


# create configs, secrets

```
kubectl apply -f ./k8s/010-configmap.yaml
kubectl apply -f ./k8s/020-secret.yaml
```


# launch services in following order
- rabbitmq_publisher

# install ingress controller
```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.1/deploy/static/provider/do/deploy.yaml
```



