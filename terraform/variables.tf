variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "moltbot-rg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "moltbot-vm"
}

variable "vm_size" {
  description = "Size of the VM"
  type        = string
  default     = "Standard_B4ms"  # 4 vCPU, 16 GB RAM
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}
