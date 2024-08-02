# Tell terraform to use the provider and select a version.
terraform {
    required_providers {
        hcloud = {
            source = "hetznercloud/hcloud"
            version = "~> 1.45"
        }
    }
}

# using the -var="hcloud_token=..." CLI option
variable "hcloud_token" {
    type = string
    sensitive = true
}

# SSH Public Key -> needs to be replaced with every new deployment
data "hcloud_ssh_key" "zabbix-ssh-key" {
  name = "Zabbix"
}

# Configure the Hetzner Cloud Provider
provider "hcloud" {
    token = var.hcloud_token
}

# Create a network
resource "hcloud_network" "Zabbix-Network" {
    name = "Ansible-Network"
    ip_range = "10.0.0.0/8"
}

# Create a sub-network
resource "hcloud_network_subnet" "Zabbix-Sub-Network" {
    type = "cloud"
    network_id = hcloud_network.Zabbix-Network.id
    ip_range = "10.10.1.0/24"
    network_zone = "eu-central"
}

# Create Ansible Controller
resource "hcloud_server" "Zabbix-Server" {
    name        = "Zabbix-Server"
    image       = "debian-12"
    # Currently: 2 vCPUs (shared), 4 GB RAM, 40 GB Disk, 20 TB Traffic, 0.006 €/h -> 3,92 €/month
    server_type = "cx22"
    location    = "fsn1"
    user_data = file("zabbix-config.yml")

    labels = {
        "env" = "test"
        "role" = "zabbix-server"
    }

    ssh_keys = [
        data.hcloud_ssh_key.zabbix-ssh-key.id
    ]

    keep_disk = true
    public_net {
        # no ipv4 address -> 1 €/month extra
        ipv4_enabled = false
        # ipv6 address for external internet access -> free
        ipv6_enabled = true
    }

    network {
        network_id = hcloud_network.Zabbix-Network.id
        ip = "10.10.1.10"
    }

    depends_on = [
        hcloud_network_subnet.Zabbix-Sub-Network
    ]
}

# Create Zabbix Agent (1)
resource "hcloud_server" "Zabbix-Agents" {
    count       = 1
    name        = "Zabbix-Agent-${count.index}"
    image       = "debian-12"
    # Currently: 2 vCPUs (shared), 4 GB RAM, 40 GB Disk, 20 TB Traffic, 0.006 €/h -> 3,92 €/month
    server_type = "cx22"
    location    = "fsn1"

    labels = {
        "env" = "test"
        "role" = "zabbix-agent"
    }

    ssh_keys = [
        data.hcloud_ssh_key.zabbix-ssh-key.id
    ]

    keep_disk = true
    public_net {
        # no ipv4 address -> 1 €/month extra
        ipv4_enabled = false
        # ipv6 address for external internet access -> free
        ipv6_enabled = true
    }

    network {
        network_id = hcloud_network.Zabbix-Network.id
        ip = "10.10.1.${count.index + 11}"
    }

    depends_on = [
        hcloud_network_subnet.Zabbix-Sub-Network
    ]
}
