# Switching from old Mini-Spinnaker (port-based routing) to Mini-Spinnaker using path-based routing

## (Re)Install Traefik

If Traefik has already been removed, you can still do this safely.

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

## Create `service-settings/gate.yml`

```bash
## TODO: Update template
mkdir -p /etc/spinnaker/.hal/default/service-settings
sudo tee -a /etc/spinnaker/.hal/default/service-settings/gate.yml <<-'EOF'

healthEndpoint: /api/v1/health

EOF
```

## Update `profiles/gate-local.yml`

```bash
## TODO: Update template
mkdir -p /etc/spinnaker/.hal/default/profiles
sudo tee -a /etc/spinnaker/.hal/default/profiles/gate-local.yml <<-'EOF'

server:
  servlet:
    context-path: /api/v1

EOF
```

## Create the Ingress

```bash
tee /etc/spinnaker/manifests/expose-spinnaker-ingress.yaml <<-'EOF'
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  labels:
    app: spin
  name: spin-ingress
  namespace: spinnaker
spec:
  rules:
  - 
    http:
      paths:
      - backend:
          serviceName: spin-deck
          servicePort: 9000
        path: /
  - 
    http:
      paths:
      - backend:
          serviceName: spin-gate
          servicePort: 8084
        path: /api/v1
EOF

# One or both of these may error.  It's fine.
kubectl -n spinnaker delete svc spin-deck-lb spin-gate-lb
kubectl -n spinnaker delete ingress spinnaker-ingress

kubectl apply -f /etc/spinnaker/manifests/expose-spinnaker-ingress.yaml
```

## Change endpoint

Run these one at a time (wait for them to complete)

```bash
## TODO: Update template

# This can be an IP or DNS
DNS_NAME_FOR_MINNAKER=http://some-hostname-pointing-to-your-instance

hal config security ui edit --override-base-url ${DNS_NAME_FOR_MINNAKER}

hal config security api edit --override-base-url ${DNS_NAME_FOR_MINNAKER}/api/v1

hal deploy apply
```
