
# Uninstall traefik

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
    '--no-deploy=traefik' \

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

kubectl -n kube-system delete helmcharts traefik

```

## Remove ingress, re-add services

```bash
kubectl -n spinnaker delete ingress spinnaker-ingress
kubectl apply -f /etc/spinnaker/manifests/expose-spinnaker.yaml
```

## Change endpoint

```bash

hal config security ui edit --override-base-url http://$(cat /etc/spinnaker/.hal/public_ip)

hal config security api edit --override-base-url http://$(cat /etc/spinnaker/.hal/public_ip):8084

hal deploy apply
```
