# Kubernetes - Digital Ocean - Drupal - Galera Cluster

Deploy a Drupal and Galera Kubernetes cluster in Digital Ocean using Terraform.

## Still to be done

This is in no shape for production yet. Use it at your own risk.

There are several part to this that need completing/improving:

* There are currently no limits for the resources of the Drupal or Galera replication controllers, giving no information to the scheduler about expected resource consumption.
* A solution needs to be found for Drupal's *file system*, currently there is only on replica of Drupal as having more that this causes two issues.
..* Each replica will need a separate *setting.php* file, going through the set-up process to generate this file means going through several pages and a different Pod could be hit on any of these page loads, switching pods during this process will restart it, making to stuck in a infinite loop. *This could be fixed by creating a persistent volume but will need some looking into first*
..* Each replica will have a separate public and private *file system*, meaning files uploaded to one replica will not be accessible from another. Causing these files to randomly appear on some page loads and be gone on others. *This could be fixed by creating a persistent volume or only using a CDN but will need some looking into first*
..* Each replica has a separate modules, themes and libraries folder, meaning installing a module either through Drush or the modules admin page will cause it to randomly be available on each page load. *This could be fixed by creating a persistent volume but will need some looking into first*
* This currently generates five 4GB Digital Ocean droplets, I feel some if not all of these droplets do not need to be this big, at this size the monthly cost would be $200. They are currently this large because smaller droplets cause the Galera pods to be killed by the replication controller and restarted as they can not find the other Pods in their cluster as these have not started quickly enough, this then devolves into a cycle as the other Pods in the cluster are created moments after this and then can not find the Pod before them. *This could be fixed by not starting pods 2 and 3 until node 1 is ready*. Even if the worker Nodes can not be reduced from 4GB it could be the case that the Master and ECTD nodes could be made smaller.
* The Galera Cluster is currently externally accessible, although this is not unusual it is not necessarily needed as Pods needing the cluster can access it through services. Removing externally access would improve security but a solution to external backups will need to be found. *This could be solved by creating backups internally and then pushing them out, environment variables would be needed for the external service*
* This README could have more information under the *Deploy details* section detailing the Drupal, Galera Cluster and Adminer components, along with some examples of the *secret* files.


## Requirements

* [Digital Ocean](https://www.digitalocean.com/) account
* Digital Ocean Token [In DO's settings/tokens/new](https://cloud.digitalocean.com/settings/tokens/new)
* [Terraform](https://www.terraform.io/)
* [Kubectl](http://kubernetes.io/docs/user-guide/prereqs/)

Do all the following steps from a development machine. It does not matter _where_ is it, as long as it is connected to the internet. This one will be subsequently used to access the cluster via `kubectl`.

## Generate private / public keys

```
ssh-keygen -t rsa -b 4096
```

System will prompt you for a filepath to save the key, we will go by `~/.ssh/id_rsa` in this tutorial.

## Add your public key in Digital Ocean control panel

[Do it here](https://cloud.digitalocean.com/settings/security). Name it and paste the public key just below `Add SSH Key`.

## Add this key to your ssh agent

```bash
eval `ssh-agent -s`
ssh-add ~/.ssh/id_rsa
```

## Invoke terraform

Put your Digitalocean token in the file `./secrets/DO_TOKEN` (that directory is mentioned in `.gitignore`, of course, so we don't leak it).

You'll also need to create some secrect files for your Galera cluster, these will be your WSREP SST User, WSREP SST Password, MySQL User MySQL Password and MySQL Root Password, and go in `./secrets/WSREP_SST_USER`, `./secrets/WSREP_SST_PASS`, `./secrets/MYSQL_USER`, `./secrets/MYSQL_PASS` and `./secrets/MYSQL_ROOT_PASS` respectively.

Then we setup the environment variables (step into `this repository` root). Note that the first variable in this script sets up the *number of workers*

```bash
. ./hack/setup_terraform.sh
```

**note** if you are using an older version of OSX and get errors running this script, you may need to replay the last line in `./hack/setup_terraform.sh` with

```bash
export TF_VAR_ssh_fingerprint=$(ssh-keygen -E MD5 -lf ~/.ssh/id_rsa.pub | awk '{print $2}' | sed 's/MD5://g')
```

After setup, call `terraform apply`

```bash
terraform apply
```

That should do! `kubectl` is configured, so you can just check the nodes (`get no`) and the pods (`get po`).

```bash
** $ kubectl get nodes **
NAME          LABELS                               STATUS
X.X.X.X   kubernetes.io/hostname=X.X.X.X   Ready     2m
Y.Y.Y.Y   kubernetes.io/hostname=Y.Y.Y.Y   Ready     2m

** $ kubectl --namespace=kube-system get pods **
NAME                                   READY     STATUS    RESTARTS   AGE
kube-apiserver-X.X.X.X            1/1       Running   0          1m
kube-controller-manager-X.X.X.X   1/1       Running   0          1m
kube-dns-v9-heab2                 4/4       Running   0          56s
kube-podmaster-X.X.X.X            2/2       Running   0          2m
kube-proxy-Y.Y.Y.Y                1/1       Running   0          34s
kube-proxy-X.X.X.X                1/1       Running   0          2m
kube-scheduler-X.X.X.X            1/1       Running   0          1m
```

## Accessing Drupal

You are good to go. You will be able you reach your Drupal site by visiting the public ip of your first worker node ("k8s-worker-01"). You can find this by using kubectl to list the nodes or by visiting the Digitalocean control panel. In the following case the public is *139.59.185.10*

```bash
$ kubectl get nodes

NAME             STATUS    AGE
139.59.171.249   Ready     1h
139.59.177.162   Ready     1h
139.59.182.99    Ready     1h
139.59.185.10    Ready     1h
```

## Accessing the Galera Cluster

Adminer has been included in this build to make accessing MySQL via the internal service IPs easier, and can be reached by visiting the public ip of your second worker node ("k8s-worker-02") which can be found as described above.

The *server ip* for accessing your cluster can be found listed under `kubectl get services` as the *CLUSTER-IP* of the *pxc-cluster* service. In the following case that is *10.3.0.2*.

```bash
** $ kubectl get services **

NAME          CLUSTER-IP   EXTERNAL-IP     PORT(S)                               AGE
adminer       10.3.0.24    139.59.182.99   80/TCP                                18m
drupal        10.3.0.167   139.59.185.10   80/TCP                                18m
kubernetes    10.3.0.1     <none>          443/TCP                               19m
pxc-cluster   10.3.0.2     <pending>       3306/TCP,4444/TCP,4567/TCP,4568/TCP   18m
pxc-node1     10.3.0.151   <none>          3306/TCP,4444/TCP,4567/TCP,4568/TCP   18m
pxc-node2     10.3.0.121   <none>          3306/TCP,4444/TCP,4567/TCP,4568/TCP   18m
pxc-node3     10.3.0.207   <none>          3306/TCP,4444/TCP,4567/TCP,4568/TCP   18m
```

You can also access the your Galera Cluster externally by using the *pxc-cluster* service's *mysql NodePort* along with the public ip of any node, the *mysql NodePort* can be found under `kubectl describe services pxc-cluster`. In the following case that is *30939*.

```bash
$ kubectl describe services pxc-cluster
Name:			        pxc-cluster
Namespace:	     	default
Labels:			      unit=pxc-cluster
Selector:	       	unit=pxc-cluster
Type:		         	LoadBalancer
IP:		            10.3.0.2
Port:			        mysql	3306/TCP
NodePort:	       	mysql	30939/TCP
Endpoints:	     	10.2.23.2:3306,10.2.23.3:3306,10.2.23.4:3306
Port:			        state-snapshot-transfer	4444/TCP
NodePort:	       	state-snapshot-transfer	30619/TCP
Endpoints:	     	10.2.23.2:4444,10.2.23.3:4444,10.2.23.4:4444
Port:		          replication-traffic	4567/TCP
NodePort:	       	replication-traffic	31808/TCP
Endpoints:	     	10.2.23.2:4567,10.2.23.3:4567,10.2.23.4:4567
Port:		         	incremental-state-transfer	4568/TCP
NodePort:	       	incremental-state-transfer	31738/TCP
Endpoints:	     	10.2.23.2:4568,10.2.23.3:4568,10.2.23.4:4568
Session Affinity:	None
No events.
```

Now, we can keep on reading to dive into the specifics.

## Deploy details

### K8s etcd host

#### Cloud config

The following unit is being configured and started

* `etcd2`

### K8s master

#### Cloud config

##### Files

The following files are `kubernetes` manifests to be loaded by `kubelet`

* `/etc/kubernetes/manifests/kube-apiserver.yaml`
* `/etc/kubernetes/manifests/kube-proxy.yaml`
* `/etc/kubernetes/manifests/kube-podmaster.yaml`
* `/srv/kubernetes/manifests/kube-controller-manager.yaml`
* `/srv/kubernetes/manifests/kube-scheduler.yaml`

##### Units

The following units are being configured and started

* `flanneld`: Specifying that it will use the `k8s-etcd` host's `etcd` service
* `docker`: Dependent on this host's `flannel`
* `kubelet`: The lowest level kubernetes element.

#### Provisions

Once we create this droplet (and get its `IP`), the TLS assets will be created locally (i.e. the development machine from we run `terraform`), and put into the directory `secrets` (which, again, is mentioned in `.gitignore`).

The following files will be provisioned into the host

* `/etc/kubernetes/ssl/ca.pem`
* `/etc/kubernetes/ssl/apiserver.pem`
* `/etc/kubernetes/ssl/apiserver-key.pem`

With some modifications to be run

```bash
sudo chmod 600 /etc/kubernetes/ssl/*-key.pem
sudo chown root:root /etc/kubernetes/ssl/*-key.pem
```

Finally, we start `kubelet`, _enable_ it and create the namespace

```bash
sudo systemctl start kubelet
sudo systemctl enable kubelet
until $(curl --output /dev/null --silent --head --fail http://127.0.0.1:8080); do printf '.'; sleep 5; done
curl -XPOST -d'{\"apiVersion\":\"v1\",\"kind\":\"Namespace\",\"metadata\":{\"name\":\"kube-system\"}}' http://127.0.0.1:8080/api/v1/namespaces
```

### K8s workers

#### Cloud config

##### Files

The following files are `kubernetes` manifests to be loaded by `kubelet`

* `/etc/kubernetes/manifests/kube-proxy.yaml`
* `/etc/kubernetes/worker-kubeconfig.yaml`

##### Units

The following units are being configured and started

* `flanneld`: Specifying that it will use the `k8s-etcd` host's `etcd` service
* `docker`: Dependent on this host's `flannel`
* `kubelet`: The lowest level kubernetes element.

### Provisions

The following files will be provisioned into the host

* `/etc/kubernetes/ssl/ca.pem`
* `/etc/kubernetes/ssl/worker.pem`
* `/etc/kubernetes/ssl/worker-key.pem`

With some modifications to be run

```bash
sudo chmod 600 /etc/kubernetes/ssl/*-key.pem
sudo chown root:root /etc/kubernetes/ssl/*-key.pem
```

We start `kubelet` and _enable_ it

```bash
sudo systemctl start kubelet
sudo systemctl enable kubelet
```

### Setup `kubectl`

After the installation is complete, `terraform` will config `kubectl` for you. The environment variables will be stored in the file `secrets/setup_kubectl.sh`.

Test your brand new cluster

```bash
kubectl get nodes
```

You should get something similar to

```
$ kubectl get nodes
NAME          LABELS                               STATUS
X.X.X.X       kubernetes.io/hostname=X.X.X.X       Ready
```

### Deploy DNS Add-on

The file `03-dns-addon.yaml` will be rendered (i.e. replace the value `DNS_SERVICE_IP`), and then `kubectl` will create the Service and Replication Controller.

### Deploy drupal with External IP

The file `04-drupal.yaml` will be rendered (i.e. replace the value `EXT_IP1`), and then `kubectl` will create the Service and Replication Controller.

To see the IP of the service, run `kubectl get svc` and look for the `EXTERNAL-IP` (should be the first worker's ext-ip).
