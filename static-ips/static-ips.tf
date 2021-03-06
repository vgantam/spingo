provider "vault" {
}

data "vault_generic_secret" "terraform_account" {
  path = "secret/${var.gcp_project}/${var.terraform_account}"
}

provider "google" {
  credentials = var.use_local_credential_file ? file("${var.terraform_account}.json") : data.vault_generic_secret.terraform_account.data[var.gcp_project]
  project     = var.gcp_project
}

resource "google_compute_address" "api" {
  for_each = var.ship_plans
  name     = "api-${each.key}"
  region   = each.value["clusterRegion"]
}

resource "google_compute_address" "api_x509" {
  for_each = var.ship_plans
  name     = "api-x509-${each.key}"
  region   = each.value["clusterRegion"]
}

resource "google_compute_address" "cloudnat" {
  for_each = var.ship_plans
  name     = "nat-${each.key}"
  region   = each.value["clusterRegion"]
  lifecycle {
    ignore_changes = [users]
  }
}

# The static IP address for Halyard is being provisioned here so that the Halyard VM can be destroyed without loosing the IP which has to be added to k8s master whitelist
resource "google_compute_address" "halyard" {
  name   = "halyard-external-ip" # needs to be dashes to satisfy regex within provider
  region = var.region
}

output "api_ips_map" {
  value = { for k, v in var.ship_plans : k => google_compute_address.api[k].address }
}

output "api_x509_ips_map" {
  value = { for k, v in var.ship_plans : k => google_compute_address.api_x509[k].address }
}


output "cloudnat_ips_map" {
  value = { for k, v in var.ship_plans : k => google_compute_address.cloudnat[k].address }
}

output "cloudnat_ips" {
  value = [for k, v in var.ship_plans : google_compute_address.cloudnat[k].address]
}

output "cloudnat_name_map" {
  value = { for k, v in var.ship_plans : k => google_compute_address.cloudnat[k].name }
}

output "halyard_ip" {
  value = google_compute_address.halyard.address
}

output "ship_plans" {
  value = var.ship_plans
}
