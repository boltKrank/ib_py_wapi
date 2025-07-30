  terraform {
    required_providers {
      infoblox = {
        source = "infobloxopen/infoblox"
        version = ">= 2.10.0"
      }
    }
  }

  provider "infoblox" {
    # Configuration options
    server = "10.193.36.90"
    username = "admin"
    password = "Infoblox@312"
  }

