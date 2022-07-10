#!/bin/bash
nfs_server_ipaddr='192.168.13.98'
mysql_folder_share='/mnt/nfsdata/website/mysql'
wp_folder_share='/mnt/nfs/website/www'
folder_mount='/home/data/'
folder_name='/root/wp'
namespace='wordpress'
wp_domain='wordpress.hoanghd.fun'

nfs_server(){
apt install nfs-common nfs-kernel-server rpcbind -y 
systemctl start rpcbind && systemctl start nfs-server

cat > /etc/exports << OEF
$mysql_folder_share  *(rw,sync,no_subtree_check,insecure)
$wp_folder_share  *(rw,sync,no_subtree_check,insecure)
OEF

mkdir -p $mysql_folder_share $wp_folder_share $folder_mount
chmod -R 777 $mysql_folder_share $wp_folder_share $folder_mount
sudo chown -R root:root $mysql_folder_share

exportfs -rav
exportfs -v
showmount -e

systemctl status nfs-server && systemctl restart nfs-server

# Test nfs mount
# nfs_server_ipaddr='192.168.12.75'
# mount -t nfs $nfs_server_ipaddr:$mysql_folder_share $folder_mount
# mount -t nfs $nfs_server_ipaddr:$wp_folder_share $folder_mount
# umount $folder_mountmkdir -p $folder_name
}

mkdir -p $folder_name  $mysql_folder_share $wp_folder_share $folder_mount
cat > $folder_name/mysql-deployment.yaml << OEF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: website-mysql
  namespace: $namespace
  labels:
    app: website-mysql
spec:
  selector:
    matchLabels:
      app: website-mysql
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: website-mysql
    spec:
      containers:
      - image: mysql:5.6
        name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql
              key: password
        - name: MYSQL_DATABASE
          valueFrom:
            secretKeyRef:
              name: mysql
              key: db_name
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: mysql
              key: db_user
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql
              key: db_pass
        ports:
        - containerPort: 3306
          name: mysql
        volumeMounts:
        - name: mysql
          mountPath: /var/lib/mysql
      volumes:
      - name: mysql
        persistentVolumeClaim:
          claimName: website-mysql-pvc
OEF

cat > $folder_name/mysql-service.yaml << OEF
apiVersion: v1
kind: Service
metadata:
  name: website-mysql
  namespace: $namespace
  labels:
    app: website-mysql
spec:
  ports:
    - port: 3306
  selector:
    app: website-mysql
OEF

cat > $folder_name/nfs-mysql-volume.yaml << OEF
kind: PersistentVolume
apiVersion: v1
metadata:
  name: website-mysql-pv
  namespace: $namespace
  labels:
    app: website-mysql
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  volumeMode: Filesystem
  persistentVolumeReclaimPolicy: Recycle
  mountOptions:
    - hard
    - nfsvers=4.1
  nfs:
    server: $nfs_server_ipaddr
    path: "$mysql_folder_share"
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: website-mysql-pvc
  namespace: $namespace
  labels:
    app: website-mysql
spec:
  selector:
    matchLabels:
      app: website-mysql
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  volumeMode: Filesystem
  volumeName: website-mysql-pv
OEF

cat > $folder_name/wordpress-deployment.yaml << OEF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: website-wp
  namespace: $namespace
  labels:
    app: website-wp
spec:
  selector:
    matchLabels:
      app: website-wp
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: website-wp
    spec:
      containers:
      - image: wordpress:5.8-apache
        imagePullPolicy: IfNotPresent
        name: wordpress
        env:
        - name: WORDPRESS_DB_HOST
          value: website-mysql
        - name: WORDPRESS_DB_NAME
          valueFrom:
            secretKeyRef:
              name: mysql
              key: db_name
        - name: WORDPRESS_DB_USER
          valueFrom:
            secretKeyRef:
              name: mysql
              key: db_user
        - name: WORDPRESS_TABLE_PREFIX
          valueFrom:
            secretKeyRef:
              name: mysql
              key: db_prefix
        - name: WORDPRESS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql
              key: db_pass
        ports:
        - containerPort: 80
          name: wordpress
        volumeMounts:
        - name: wordpress-files
          mountPath: /var/www/html
      volumes:
      - name: wordpress-files
        persistentVolumeClaim:
          claimName: website-wp-pvc
OEF

cat > $folder_name/wordpress-service.yaml << OEF
apiVersion: v1
kind: Service
metadata:
  name: website-wp
  namespace: $namespace
  labels:
    app: website-wp
spec:
  ports:
    - port: 80
  selector:
    app: website-wp
  type: LoadBalancer
OEF

cat > $folder_name/nfs-wordpress-volume.yaml << OEF
kind: PersistentVolume
apiVersion: v1
metadata:
  name: website-wp-pv
  namespace: $namespace
  labels:
    app: website-wp
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    server: $nfs_server_ipaddr
    path: "$wp_folder_share"
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: website-wp-pvc
  namespace: $namespace
  labels:
    app: website-wp
spec:
  selector:
    matchLabels:
      app: website-wp
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
  volumeName: website-wp-pv
OEF

cat > $folder_name/secrets.yaml << OEF
apiVersion: v1
kind: Secret
metadata:
  name: mysql
  namespace: $namespace
  labels:
    app: website-wp
type: Opaque
data:
  db_prefix: d3Bf
  db_name: ZGVtbw==
  db_user: ZGVtby11c2Vy
  db_pass: ZGVtby1wYXNz
  username: bXlzcWwtYWRtaW4=
  password: bXlwYXNz
OEF

cat > $folder_name/secrets.yaml << OEF
apiVersion: v1
kind: Secret
metadata:
  name: mysql
  namespace: $namespace
  labels:
    app: website-wp
type: Opaque
data:
  db_prefix: d3Bf
  db_name: ZGVtbw==
  db_user: ZGVtby11c2Vy
  db_pass: ZGVtby1wYXNz
  username: bXlzcWwtYWRtaW4=
  password: bXlwYXNz
OEF

cat > $folder_name/ingress.yaml << OEF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: website
  namespace: $namespace
  labels:
    app: website-wp
  annotations:
    kubernetes.io/ingress.class: nginx 
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/add-base-url: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
spec:
#   tls:
#   - hosts:
#     - $wp_domain
#     secretName: ssl-$wp_domain
  rules:
  - host: $wp_domain
    http:
      paths:
        - path: /
          pathType: Prefix
          backend:
            service:
                name: website-wp
                port:
                  number: 80
OEF

cat > $folder_name/mysql-volume.yaml << OEF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: website-mysql-pv
  namespace: $namespace
  labels:
    app: website-mysql
spec:
  storageClassName: website-mysql
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "$mysql_folder_share"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: website-mysql-pvc
  namespace: $namespace
  labels:
    app: website-mysql
spec:
  storageClassName: website-mysql
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
OEF

cat > $folder_name/wordpress-volume.yaml << OEF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: website-wp-pv
  namespace: $namespace
  labels:
    app: website-wp
spec:
  storageClassName: website-wp
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteMany
  hostPath:
    path: "$wp_folder_share"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: website-wp-pvc
  namespace: $namespace
  labels:
    app: website-wp
spec:
  storageClassName: website-wp
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
OEF

kubectl create namespace $namespace
kubectl apply -f $folder_name/secrets.yaml 
kubectl apply -f $folder_name/mysql-volume.yaml
kubectl apply -f $folder_name/wordpress-volume.yaml
kubectl apply -f $folder_name/mysql-deployment.yaml
kubectl apply -f $folder_name/mysql-service.yaml
kubectl apply -f $folder_name/wordpress-deployment.yaml
kubectl apply -f $folder_name/wordpress-service.yaml
kubectl apply -f $folder_name/ingress.yaml
