output "vm_public_ip" {
  description = "Public IP address of the VM"
  value       = azurerm_public_ip.moltbot.ip_address
}

output "vm_private_ip" {
  description = "Private IP address of the VM"
  value       = azurerm_network_interface.moltbot.private_ip_address
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.moltbot.ip_address}"
}

output "gateway_url" {
  description = "URL for Moltbot Gateway"
  value       = "http://${azurerm_public_ip.moltbot.ip_address}:18789"
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.moltbot.name
}
