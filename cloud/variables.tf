
# Zugriffsinformationen

variable "url" {
  description = "Evtl. URL fuer den Zugriff auf das API des Racks Servers"
  type        = string
  default     = "unknown"
}

# Umgebungsvariable TF_VAR_key ablegen
variable "key" {
  description = "API Key, Token etc. fuer Zugriff"
  type        = string
  sensitive   = true
  default     = "unknown"
}

variable "vpn" {
  description = "Optional VPN welches eingerichtet werden soll"
  type        = string
  default     = "unknown"
}

variable "vm_per_host" {
  description = "Anzahl VMs welche pro VM Host angelegt werden sollen"
  type        = number
  default     = 1
}