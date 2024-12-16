variable "Region" {
  type = map(string)
}
variable "Project" {
  type = string
}
variable "Main_Cidr" {
  type = string
}
# variable "public_Cidr" {
#   type = list(any)
# }
# variable "private_Cidr" {
#   type = list(any)
# }
variable "az_count" {
  type = number
}
variable "subnet_per_az" {
  type = number
}
variable "ami" {
  type = string
}