provider "google" {
  credentials = file("xxx.json")# here your credentials
  project     = var.project
  region      = var.region
}

resource "google_compute_network" "vpc_network" {
  name = "test-vpc-network"
}

resource "google_compute_subnetwork" "subnet" {
  name          = "my-subnet"
  ip_cidr_range = "10.0.1.0/24"  
  network       = google_compute_network.vpc_network.name
  region        = "us-central1"
}

resource "google_compute_address" "lb_ip" {
  name = "lb-ip"
}

resource "null_resource" "get_lb_ip" {
  provisioner "local-exec" {
    command = "gcloud --project=${var.project} compute addresses describe ${google_compute_address.lb_ip.name} --region=${var.region} --format='value(address)'"
    interpreter = ["powershell", "-command"]
    environment = {
      CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE = "xxx.json")# here your credentials
    }
  }

  
  triggers = {
    always_run = timestamp()
  }
}

resource "google_compute_target_pool" "lb_target_pool" {
  name = "lb-target-pool"
}

resource "google_compute_http_health_check" "lb_health_check" {
  name               = "lb-health-check"
  request_path       = "/"
  check_interval_sec = 10
  timeout_sec        = 5
}

resource "google_container_cluster" "gke_cluster" {
  name     = "test-gke-cluster"
  location = "us-central1"
  initial_node_count = 3  

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
  
  node_config {
    tags = ["gke-node"]
  }
  
  private_cluster_config {
    enable_private_endpoint = true
    enable_private_nodes     = true
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }
  
  addons_config {
    http_load_balancing {
      disabled = false
    }
  }
}

resource "google_compute_instance" "bastion_host" {
  name         = "bastion-host"
  machine_type = "e2-medium"
  zone         = "us-central1-a"  

  boot_disk {
    auto_delete = true

    initialize_params {
      image = "ubuntu-2004-focal-v20230724"
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {}
  }
}

locals {
  gke_node_disk_size_gb = 50  
  gke_node_count        = 3   
  total_ssd_storage_gb  = local.gke_node_disk_size_gb * local.gke_node_count
}

data "local_file" "org_policy_data" {
  filename = "../org_policy.json"
}

locals {
  enforced_ssd_quota_gb  = true
  available_ssd_quota_gb = local.enforced_ssd_quota_gb ? 500 : local.total_ssd_storage_gb
}

locals {
  adjusted_node_count = min(local.gke_node_count, floor(local.available_ssd_quota_gb / local.gke_node_disk_size_gb))
}

resource "google_compute_instance" "k8s_slaves" {
  count        = local.adjusted_node_count  
  name         = "k8s-node-${count.index}"
  machine_type = "e2-medium"
  zone         = "us-central1-a"  

  boot_disk {
    initialize_params {
      image = "ubuntu-2004-focal-v20230724"
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {}
  }
}

output "actual_gke_node_count" {
  value = local.adjusted_node_count
}

output "node_ips" {
  value = google_compute_instance.k8s_slaves.*.network_interface.0.access_config.0.nat_ip
}

output "load_balancer_ip" {
  value = google_compute_address.lb_ip.address
}


