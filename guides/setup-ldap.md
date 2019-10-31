
# Set up LDAP (Futurama container)

Create this manifest:

```yml
# ldap.yml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ldap
  labels:
    app: ldap
  namespace: spinnaker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ldap
  template:
    metadata:
      labels:
        app: ldap
    spec:
      containers:
      - name: ldap
        image: rroemhild/test-openldap:latest
        ports:
        - containerPort: 389
          protocol: TCP
        - containerPort: 636
          protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: ldap
  namespace: spinnaker
spec:
  ports:
    - port: 389
      name: ldap
      protocol: TCP
      targetPort: 389
    - port: 636
      name: ldaps
      protocol: TCP
      targetPort: 636
  selector:
    app: ldap
  type: ClusterIP
```

Create it:

```bash
kubectl apply -f ldap.yml
```

## Enable LDAP AuthN

```bash
hal config security authn ldap edit \
  --user-search-filter "(uid={0})" \
  --user-search-base "ou=people,dc=planetexpress,dc=com" \
  --url "ldap://ldap.spinnaker:389"

hal config security authn ldap enable
```

Remove settings-local.js authEnabled flag:

 (We can't remove the file completely cause of artifactrewrite, and can't explicitly set it to false, so we comment it)

```bash
sed -i 's|^window.spinnakerSettings.authEnabled|// window.spinnakerSettings.authEnabled|g' \
  /etc/spinnaker/.hal/default/profiles/settings-local.js
```

Disable basic auth:

```bash
sed -i 's/enabled: .*/enabled: false/g' \
  /etc/spinnaker/.hal/default/profiles/gate-local.yml
```

```bash
hal deploy apply
```

## Enable LDAP AuthZ

**Must get into Halyard container:**

```bash
kubectl -n spinnaker get pods

# Grab name of halyard pod
kubectl -n spinnaker exec -it <HALYARD_POD_NAME> bash
```

```bash
hal config security authz ldap edit \
    --url 'ldap://ldap.spinnaker:389' \
    --manager-dn 'cn=Hubert J. Farnsworth,ou=people,dc=planetexpress,dc=com' \
    --manager-password \
    --user-search-base 'dc=planetexpress,dc=com' \
    --user-search-filter '(uid={0})' \
    --group-search-base 'dc=planetexpress,dc=com' \
    --group-search-filter '(member={0})' \
    --group-role-attributes cn

 hal config security authz edit --type ldap
 hal config security authz enable
```

## Apply changes

```bash
hal deploy apply
```
