locals {
  private_subnet_ids = [for i in range(length(local.selected_azs) * var.subnet_per_az) : aws_subnet.Subnet[i].id if !(i % var.subnet_per_az == 0)]
  public_subnet_ids = [for i in range(length(local.selected_azs) * var.subnet_per_az) : aws_subnet.Subnet[i].id if (i % var.subnet_per_az == 0)]
  selected_azs = slice(data.aws_availability_zones.available.names,0,var.az_count)








}