# Workspace z.B. "aws-m122" → ["aws", "m122"]
locals {
  workspace_parts = split("-", terraform.workspace)
}

# Provider-Teil (multipass, aws, azure, maas, ...)
locals {
  cloud_provider = length(local.workspace_parts) > 0 ? local.workspace_parts[0] : "default"
  modul          = length(local.workspace_parts) > 1 ? local.workspace_parts[1] : ""
}

# Mapping Provider → Modul-Source
locals {
  module_sources = {
    multipass = "git::https://github.com/mc-b/terraform-lerncloud-multipass.git?ref=v2.0.0"
    aws       = "git::https://github.com/mc-b/terraform-lerncloud-aws.git?ref=v2.0.0"
    azure     = "git::https://github.com/mc-b/terraform-lerncloud-azure.git?ref=v2.0.0"
    gcp       = "git::https://github.com/mc-b/terraform-lerncloud-gcp.git?ref=v2.0.0"
    maas      = "git::https://github.com/mc-b/terraform-lerncloud-maas.git?ref=v2.0.0"
    lernmaas  = "git::https://github.com/mc-b/terraform-lerncloud-lernmaas.git?ref=v2.0.0"
    # fallback default
    default = "git::https://github.com/mc-b/terraform-lerncloud-maas.git?ref=v2.0.0"
  }
}

# Provider anhand Workspace wählen
locals {
  selected_source = lookup(local.module_sources, local.cloud_provider, local.module_sources["default"])
}
