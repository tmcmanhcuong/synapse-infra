# -----------------------------------------------------------------------------
# Synapse Production Environment
# -----------------------------------------------------------------------------

project     = "synapse"
environment = "prod"
aws_region  = "ap-southeast-1"

# Network
vpc_cidr = "10.0.0.0/16"

public_subnet_cidrs = [
  "10.0.0.0/20",  # ap-southeast-1a
  "10.0.16.0/20", # ap-southeast-1b
]

app_subnet_cidrs = [
  "10.0.32.0/20", # ap-southeast-1a
  "10.0.48.0/20", # ap-southeast-1b
]

data_subnet_cidrs = [
  "10.0.64.0/20", # ap-southeast-1a
  "10.0.80.0/20", # ap-southeast-1b
]

# Security
allowed_web_cidrs = ["0.0.0.0/0"]
app_port          = 8080

# Observability
alert_email = "tmcmanhcuong@gmail.com"
