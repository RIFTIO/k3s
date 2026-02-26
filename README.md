The script install-k3s.sh  - can be run as root  and it will do the following
-	Checks for root privileges - K3s installation requires root access
-	Detects and updates the OS - Works with Ubuntu, Debian, CentOS, RHEL, Rocky, Alma, and Fedora
-	Configures firewall rules - Opens necessary ports for K3s
-	Disables swap - Required for Kubernetes to function properly
-	Loads kernel modules - Sets up overlay and br_netfilter
-	Configures networking - Sets up sysctl parameters for container networking
-	Installs K3s - Uses the official installation script
-	Verifies installation - Checks if the service is running and nodes are ready
-	Sets up kubectl access - Provides kubeconfig information
-	Installs Helm along with pre-requisites
-	Sets up Helm to access K3s

# Prerequisites and notes # 

* /var cannot be mounted with the NOEXEC option 
* allow for an extra 30 GB of disk space and 100 MB of RAM for k8s itself, above and beyond the requirements of your
applications.
* single node instances often have conflicts over the routing of traffic to particular host ports, e.g. 22. Any ingress 
rules must take this into account. 


# The directory #

hello-world-nginx has this structure

    hello-world-nginx/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── configmap.yaml
        ├── deployment.yaml
        └── service.yaml

To deploy this small K3s application use this command

```bash 
helm install hello-world ./hello-world-nginx
```

To delete use

```bash
helm delete hello-world
```

If you make any changes to the hello-world-nginx files then you can upgrade the deployment with

```bash
helm upgrade hello-world ./hello-world-nginx
```

Once installed you should be able to viewed it by pointing your browser or curl/wget at

    http://<VM IP>:30080
    http://<Server IP>


