terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "moltbot" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    environment = "production"
    managed_by  = "terraform"
  }
}

# Virtual Network
resource "azurerm_virtual_network" "moltbot" {
  name                = "${var.vm_name}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.moltbot.location
  resource_group_name = azurerm_resource_group.moltbot.name
}

# Subnet
resource "azurerm_subnet" "moltbot" {
  name                 = "${var.vm_name}-subnet"
  resource_group_name  = azurerm_resource_group.moltbot.name
  virtual_network_name = azurerm_virtual_network.moltbot.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "moltbot" {
  name                = "${var.vm_name}-nsg"
  location            = azurerm_resource_group.moltbot.location
  resource_group_name = azurerm_resource_group.moltbot.name

  # SSH
  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Moltbot Gateway
  security_rule {
    name                       = "AllowMoltbot"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "18789"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # HTTPS
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Public IP
resource "azurerm_public_ip" "moltbot" {
  name                = "${var.vm_name}-pip"
  resource_group_name = azurerm_resource_group.moltbot.name
  location            = azurerm_resource_group.moltbot.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Network Interface
resource "azurerm_network_interface" "moltbot" {
  name                = "${var.vm_name}-nic"
  location            = azurerm_resource_group.moltbot.location
  resource_group_name = azurerm_resource_group.moltbot.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.moltbot.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.moltbot.id
  }
}

# Connect NSG to NIC
resource "azurerm_network_interface_security_group_association" "moltbot" {
  network_interface_id      = azurerm_network_interface.moltbot.id
  network_security_group_id = azurerm_network_security_group.moltbot.id
}

# Virtual Machine
resource "azurerm_linux_virtual_machine" "moltbot" {
  name                = var.vm_name
  resource_group_name = azurerm_resource_group.moltbot.name
  location            = azurerm_resource_group.moltbot.location
  size                = var.vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.moltbot.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {}))

  tags = {
    environment = "production"
    managed_by  = "terraform"
  }
}
