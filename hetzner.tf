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

# Generate a random password for Postgres
resource "random_password" "postgres_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Create Zabbix Server
resource "hcloud_server" "Zabbix-Server" {
    name        = "Zabbix-Server"
    image       = "debian-12"
    server_type = "cx22"
    location    = "fsn1"
    user_data = file("zabbix-config.yml")

    labels = {
        "env"  = "test"
        "role" = "zabbix-server"
    }

    ssh_keys = [
        data.hcloud_ssh_key.zabbix-ssh-key.id
    ]

    keep_disk = true
    public_net {
        # needs to be enabled for Github access -> 1 €/month extra
        ipv4_enabled = true
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

    # Use templatefile function to populate the cloud-config file with dynamic values
    user_data = templatefile("zabbix-agent-cloud-config.yml", {
        ip_address = hcloud_server.Zabbix-Server.ipv4_address
        hostname   = "Zabbix-Agent-${count.index}"
    })

    labels = {
        "env" = "test"
        "role" = "zabbix-agent"
    }

    ssh_keys = [
        data.hcloud_ssh_key.zabbix-ssh-key.id
    ]

    keep_disk = true
    public_net {
        # needs to be enabled for Github access -> 1 €/month extra
        ipv4_enabled = true
        # ipv6 address for external internet access -> free
        ipv6_enabled = true
    }

    network {
        network_id = hcloud_network.Zabbix-Network.id
        ip = "10.10.1.${count.index + 11}"
    }

    depends_on = [
        hcloud_network_subnet.Zabbix-Sub-Network,
        hcloud_server.Zabbix-Server
    ]
}

output "Zabbix-Server-IPv4" {
  value = hcloud_server.Zabbix-Server.ipv4_address
  description = "The IPv4 address of the Zabbix Server"
}

output "Zabbix-Server-IPv6" {
  value = hcloud_server.Zabbix-Server.ipv6_address
  description = "The IPv6 address of the Zabbix Server"
}

output "Zabbix-Agent-IPv4" {
  value = hcloud_server.Zabbix-Agents[*].ipv4_address
  description = "The IPv4 addresses of the Zabbix Agents"
}

output "Zabbix-Agent-IPv6" {
  value = hcloud_server.Zabbix-Agents[*].ipv6_address
  description = "The IPv6 addresses of the Zabbix Agents"
}

output "next_steps" {
  value = <<EOT

  Next Steps:
  1. SSH into the Zabbix Server:
    ssh root@${hcloud_server.Zabbix-Server.ipv4_address}
  2. Check the Output of the Cloud-Init Script:
    cat /var/log/cloud-init-output.log
  3. Check the Status of the Docker Containers:
    docker ps
  4. Open the Zabbix Web Interface:
    http://${hcloud_server.Zabbix-Server.ipv4_address}
  5. Login with the following credentials:
    Username: Admin
    Password: zabbix
  6. SSH into the Zabbix Agent:
    ssh root@${hcloud_server.Zabbix-Agents[0].ipv4_address}
  7. Check the Zabbix Agent Docker container:
    docker ps | grep zabbix-agent
  8. Add the Zabbix Agent to the Zabbix Server:
    Go to Data collection -> Hosts or Monitoring -> Hosts
    Click on Create host to the right (or on the host name to edit an existing host)
    Hostname: Zabbix-Agent-0
    Groups: Linux Servers
    Agent interfaces: IP Address: ${hcloud_server.Zabbix-Agents[0].ipv4_address}
    Templates: Template OS Linux
    Agent: Zabbix Agent
    Save
    For more information: https://www.zabbix.com/documentation/current/en/manual/config/hosts/host
  EOT

  description = "Next steps to configure the Zabbix Server and Agent"
}
