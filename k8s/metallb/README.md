# MetalLB

Installed from upstream manifests:

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
kubectl apply -f ipaddresspool.yaml
kubectl apply -f l2advertisement.yaml
```
