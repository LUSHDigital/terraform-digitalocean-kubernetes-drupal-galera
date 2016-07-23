###############################################################################
#
# A simple K8s cluster in DO
#
###############################################################################


###############################################################################
#
# Get variables from command line or environment
#
###############################################################################


variable "do_token" {}
variable "wsrep_sst_user" {}
variable "wsrep_sst_pass" {}
variable "mysql_user" {}
variable "mysql_pass" {}
variable "mysql_root_pass" {}
variable "pub_key" {}
variable "pvt_key" {}
variable "ssh_fingerprint" {}
variable "number_of_workers" {}


###############################################################################
#
# Specify provider
#
###############################################################################


provider "digitalocean" {
  token = "${var.do_token}"
}


###############################################################################
#
# Etcd host
#
###############################################################################


resource "digitalocean_droplet" "k8s_etcd" {
    image = "coreos-stable"
    name = "k8s-etcd"
    region = "lon1"
    size = "4gb"
    user_data = "${file("00-etcd.yaml")}"
    ssh_keys = [
        "${var.ssh_fingerprint}"
    ]
}


###############################################################################
#
# Master host's user data template
#
###############################################################################


resource "template_file" "master_yaml" {
    template = "${file("01-master.yaml")}"
    vars {
        DNS_SERVICE_IP = "10.3.0.10"
        ETCD_IP = "${digitalocean_droplet.k8s_etcd.ipv4_address}"
        K8S_SERVICE_IP = "10.3.0.1"
        POD_NETWORK = "10.2.0.0/16"
        SERVICE_IP_RANGE = "10.3.0.0/24"
    }
}


###############################################################################
#
# Master host
#
###############################################################################


resource "digitalocean_droplet" "k8s_master" {
    image = "coreos-stable"
    name = "k8s-master"
    region = "lon1"
    size = "4gb"
    user_data = "${template_file.master_yaml.rendered}"
    ssh_keys = [
        "${var.ssh_fingerprint}"
    ]

    # Node created, let's generate the TLS assets
    provisioner "local-exec" {
        command = <<EOF
            $PWD/hack/generate-tls-assets.sh \
              ${digitalocean_droplet.k8s_master.ipv4_address}
EOF
    }

    # Provision Master's TLS Assets
    provisioner "file" {
        source = "./secrets/ca.pem"
        destination = "/home/core/ca.pem"
        connection {
            user = "core"
        }
    }

    provisioner "file" {
        source = "./secrets/apiserver.pem"
        destination = "/home/core/apiserver.pem"
        connection {
            user = "core"
        }
    }

    provisioner "file" {
        source = "./secrets/apiserver-key.pem"
        destination = "/home/core/apiserver-key.pem"
        connection {
            user = "core"
        }
    }

    provisioner "remote-exec" {
        inline = [
            "sudo mkdir -p /etc/kubernetes/ssl",
            "sudo mv /home/core/{ca,apiserver,apiserver-key}.pem /etc/kubernetes/ssl/.",
            "sudo chmod 600 /etc/kubernetes/ssl/*-key.pem",
            "sudo chown root:root /etc/kubernetes/ssl/*-key.pem"
        ]
        connection {
            user = "core"
        }
    }

    # Start kubelet and create kube-system namespace
    provisioner "remote-exec" {
        inline = [
            "sudo systemctl start kubelet",
            "sudo systemctl enable kubelet",
            "until $(curl --output /dev/null --silent --head --fail http://127.0.0.1:8080); do printf '.'; sleep 5; done",
            "curl -XPOST -H 'Content-type: application/json' -d'{\"apiVersion\":\"v1\",\"kind\":\"Namespace\",\"metadata\":{\"name\":\"kube-system\"}}' http://127.0.0.1:8080/api/v1/namespaces"
        ]
        connection {
            user = "core"
        }
    }
}


###############################################################################
#
# Worker host's user data template
#
###############################################################################


resource "template_file" "worker_yaml" {
    template = "${file("02-worker.yaml")}"
    vars {
        DNS_SERVICE_IP = "10.3.0.10"
        ETCD_IP = "${digitalocean_droplet.k8s_etcd.ipv4_address}"
        MASTER_HOST = "${digitalocean_droplet.k8s_master.ipv4_address}"
    }
}


###############################################################################
#
# Worker hosts
#
###############################################################################


resource "digitalocean_droplet" "k8s_worker" {
    count = "${var.number_of_workers}"

    image = "coreos-stable"
    name = "${format("k8s-worker-%02d", count.index + 1)}"
    region = "lon1"
    size = "4gb"
    user_data = "${template_file.worker_yaml.rendered}"
    ssh_keys = [
        "${var.ssh_fingerprint}"
    ]

    # Provision Master's TLS Assets
    provisioner "file" {
        source = "./secrets/ca.pem"
        destination = "/home/core/ca.pem"
        connection {
            user = "core"
        }
    }

    provisioner "file" {
        source = "./secrets/apiserver.pem"
        destination = "/home/core/worker.pem"
        connection {
            user = "core"
        }
    }

    provisioner "file" {
        source = "./secrets/apiserver-key.pem"
        destination = "/home/core/worker-key.pem"
        connection {
            user = "core"
        }
    }

    provisioner "remote-exec" {
        inline = [
            "sudo mkdir -p /etc/kubernetes/ssl",
            "sudo mv /home/core/{ca,worker,worker-key}.pem /etc/kubernetes/ssl/.",
            "sudo chmod 600 /etc/kubernetes/ssl/*-key.pem",
            "sudo chown root:root /etc/kubernetes/ssl/*-key.pem"
        ]
        connection {
            user = "core"
        }
    }

    # Start kubelet
    provisioner "remote-exec" {
        inline = [
            "sudo systemctl start kubelet",
            "sudo systemctl enable kubelet"
        ]
        connection {
            user = "core"
        }
    }
}

###############################################################################
#
# Make config file and export variables for kubectl
#
###############################################################################


resource "null_resource" "setup_kubectl" {
    depends_on = ["digitalocean_droplet.k8s_worker"]
    provisioner "local-exec" {
        command = <<EOF
            echo export MASTER_HOST=${digitalocean_droplet.k8s_master.ipv4_address} > $PWD/secrets/setup_kubectl.sh
            echo export CA_CERT=$PWD/secrets/ca.pem >> $PWD/secrets/setup_kubectl.sh
            echo export ADMIN_KEY=$PWD/secrets/admin-key.pem >> $PWD/secrets/setup_kubectl.sh
            echo export ADMIN_CERT=$PWD/secrets/admin.pem >> $PWD/secrets/setup_kubectl.sh
            . $PWD/secrets/setup_kubectl.sh
            kubectl config set-cluster default-cluster \
                --server=https://$MASTER_HOST --certificate-authority=$CA_CERT
            kubectl config set-credentials default-admin \
                 --certificate-authority=$CA_CERT --client-key=$ADMIN_KEY --client-certificate=$ADMIN_CERT
            kubectl config set-context default-system --cluster=default-cluster --user=default-admin
            kubectl config use-context default-system
EOF
    }
}

resource "null_resource" "deploy_dns_addon" {
    depends_on = ["null_resource.setup_kubectl"]
    provisioner "local-exec" {
        command = <<EOF
            sed -e "s/\$DNS_SERVICE_IP/10.3.0.10/" < 03-dns-addon.yaml > ./secrets/03-dns-addon.rendered.yaml
            until kubectl get pods 2>/dev/null; do printf '.'; sleep 5; done
            kubectl create -f ./secrets/03-dns-addon.rendered.yaml
EOF
    }
}

resource "null_resource" "deploy_adminer" {
    depends_on = ["null_resource.setup_kubectl"]
    provisioner "local-exec" {
        command = <<EOF
            sed -e "s/\$EXT_IP2/${digitalocean_droplet.k8s_worker.1.ipv4_address}/" < 04-adminer.yaml > ./secrets/04-adminer.rendered.yaml
            until kubectl get pods 2>/dev/null; do printf '.'; sleep 5; done
            kubectl create -f ./secrets/04-adminer.rendered.yaml

EOF
    }
}

resource "null_resource" "deploy_galera_cluster_service" {
    depends_on = ["null_resource.setup_kubectl"]
    provisioner "local-exec" {
        command = <<EOF
            until kubectl get pods 2>/dev/null; do printf '.'; sleep 5; done
            kubectl create -f 05-pxc-cluster-service.yaml

EOF
    }
}

resource "null_resource" "deploy_galera_node1" {
    depends_on = ["null_resource.setup_kubectl"]
    provisioner "local-exec" {
        command = <<EOF
            until kubectl get pods 2>/dev/null; do printf '.'; sleep 5; done
            kubectl create -f 06-pxc-node1.yaml

EOF
    }
}

resource "null_resource" "deploy_galera_node2" {
    depends_on = ["null_resource.setup_kubectl"]
    provisioner "local-exec" {
        command = <<EOF
            until kubectl get pods 2>/dev/null; do printf '.'; sleep 5; done
            kubectl create -f 07-pxc-node2.yaml

EOF
    }
}

resource "null_resource" "deploy_galera_node3" {
    depends_on = ["null_resource.setup_kubectl"]
    provisioner "local-exec" {
        command = <<EOF
            until kubectl get pods 2>/dev/null; do printf '.'; sleep 5; done
            kubectl create -f 08-pxc-node3.yaml

EOF
    }
}

resource "null_resource" "deploy_drupal" {
    depends_on = ["null_resource.setup_kubectl"]
    provisioner "local-exec" {
        command = <<EOF
            sed -e "s/\$EXT_IP1/${digitalocean_droplet.k8s_worker.0.ipv4_address}/" < 09-drupal.yaml > ./secrets/09-drupal.rendered.yaml
            until kubectl get pods 2>/dev/null; do printf '.'; sleep 5; done
            kubectl create -f ./secrets/09-drupal.rendered.yaml

EOF
    }
}
