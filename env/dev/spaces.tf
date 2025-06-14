module "spaces" {
  for_each      = toset(var.public-space-names)
  source        = "terraform-do-modules/spaces/digitalocean"
  version       = "1.0.0"
  name          = each.key
  environment   = var.env
  acl           = "public-read"
  force_destroy = false
  region        = var.region
  # policy = jsonencode({
  #       "Version" : "2012-10-17",
  #       "Statement" : [
  #         {
  #           "Sid" : "IPAllow",
  #           "Effect" : "Deny",
  #           "Principal" : "*",
  #           "Action" : "s3:*",
  #           "Resource" : [
  #             "arn:aws:s3:::space-name",
  #             "arn:aws:s3:::space-name/*"
  #           ],
  #           "Condition" : {
  #             "NotIpAddress" : {
  #               "aws:SourceIp" : "0.0.0.0/0"
  #             }
  #           }
  #         }
  #       ]
  #     })
}