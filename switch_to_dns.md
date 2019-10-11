
# Switch Spinnaker endpoint from two ports to two DNS names

## (Re)Install Traefik

```bash
sudo tee /etc/systemd/system/k3s.service <<-'EOF'
[Unit]
Description=Lightweight Kubernetes
Documentation=https://k3s.io
After=network-online.target

[Service]
Type=notify
EnvironmentFile=/etc/systemd/system/k3s.service.env
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/k3s \
    server \

KillMode=process
Delegate=yes
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl restart k3s
```

## Create Ingress

Replace spinnaker.armory.internal and gate.armory.internal with DNS names pointing to this instance:

```bash
sudo tee /etc/spinnaker/manifests/ingress.yml <<-'EOF'
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: spinnaker-ingress
  namespace: spinnaker
  labels:
    app: "spin"
  annotations:
    kubernetes.io/ingress.class: "traefik"

spec:
  rules:
  - host: spinnaker.armory.internal
    http:
      paths:
      - backend:
          serviceName: spin-deck
          servicePort: 9000
        path: /
  - host: gate.armory.internal
    http:
      paths:
      - backend:
          serviceName: spin-gate
          servicePort: 8084
        path: /
EOF

kubectl -n spinnaker delete svc spin-deck-lb spin-gate-lb
kubectl apply -f /etc/spinnaker/manifests/ingress.yml

```

## Change endpoint

Run these one at a time (wait for them to complete)

```bash
hal config security ui edit --override-base-url http://spinnaker.armory.internal

hal config security api edit --override-base-url http://gate.armory.internal

hal deploy apply
```
