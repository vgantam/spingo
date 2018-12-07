provider "vault" {
  address = "${var.vault_address}"
}

data "vault_generic_secret" "terraform-account" {
  path = "secret/${var.terraform_account}"
}

provider "google" {
  credentials = "${data.vault_generic_secret.terraform-account.data[var.gcp_project]}"
  project     = "${var.gcp_project}"
  region      = "${var.gcp_region}"
}
provider "google-beta" {
  credentials = "${data.vault_generic_secret.terraform-account.data[var.gcp_project]}"
  project     = "${var.gcp_project}"
  region      = "${var.gcp_region}"
}

data "google_project" "project" {}

module "spin-k8s-cluster" {
  source                          = "./modules/gke"
  cluster_name                    = "spinnaker"
  cluster_region                  = "us-east1"
  enable_legacy_abac              = true
  master_authorized_network_cidrs = []
}

module "halyard-storage" {
  source      = "./modules/gcp-bucket"
  gcp_project = "${var.gcp_project}"
  bucket_name = "halyard"
}

module "k8s-spinnaker-service-account" {
  source                    = "./modules/gke/k8s-service-account"
  service_account_name      = "spinnaker"
  service_account_namespace = "spinnaker"
  host                      = "${module.spin-k8s-cluster.host}"
  client_certificate        = "${module.spin-k8s-cluster.client_certificate}"
  client_key                = "${module.spin-k8s-cluster.client_key}"
  cluster_ca_certificate    = "${module.spin-k8s-cluster.cluster_ca_certificate}"
}

# to retrieve the keys for this for use outside of terraform, run 
# `vault read -format json -field=data secret/spinnaker-gcs-account > somefile.json`
module "spinnaker-gcp-service-account" {
  source               = "./modules/gcp-service-account"
  service_account_name = "spinnaker-gcs-account"
  vault_address        = "${var.vault_address}"
}
