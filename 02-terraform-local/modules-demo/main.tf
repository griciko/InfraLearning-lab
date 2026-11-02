module "greeting_one" {
  source   = "../modules/greeting-file"
  filename = "${path.module}/greeting1.txt"
  message  = "First greeting from a module"
}

module "greeting_two" {
  source   = "../modules/greeting-file"
  filename = "${path.module}/greeting2.txt"
  message  = "Second greeting from a module"
}