# define primary AWS provider
provider "aws" {
   region = "${var.aws_region}"
   access_key = "${var.aws_access_key}"
   secret_key = "${var.aws_secret_key}"
}

# define secondary AWS provider required by some AWS services hosted primarily on US-EAST-1
provider "aws" {
  alias  = "east"
  region = "us-east-1"
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
}

variable "aws_region" {
    default = "eu-west-1"
}
variable "aws_access_key" {
    description = "AWS Access Key"
}

variable "aws_secret_key" {
    description = "AWS Secret Key"
}

variable "domain" {
    description = "Domain used to access site."
    default= "experiments.georgevella.com"
}

# S3 bucket

resource "aws_s3_bucket" "site_content" {
    bucket = "demo7-staticsite"
    acl    = "public-read"
    website {
        index_document = "index.html"
        error_document = "404.html"
    }
    policy = <<POLICY
    {
        "Version":"2012-10-17",
        "Statement":[{
            "Sid":"PublicReadForGetBucketObjects",
            "Effect":"Allow",
            "Principal": "*",
            "Action":"s3:GetObject",
            "Resource":["arn:aws:s3:::demo7-staticsite/*"]
            }
        ]
    }
POLICY

}

# cloudfront

data "aws_acm_certificate" "public_https_certificate" {
  provider = "aws.east"
  domain   = "${var.domain}"
}

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = "${aws_s3_bucket.site_content.website_endpoint}"
    origin_id   = "website_bucket_origin"

    # in static website mode buckets can only be accessed via HTTP
    custom_origin_config {
      origin_protocol_policy = "http-only"
      http_port              = "80"
      https_port             = "443"
      origin_ssl_protocols   = ["TLSv1"]
    }
  }

  enabled          = true
  is_ipv6_enabled  = true
  aliases          = ["${var.domain}"]
#  price_class      = "${var.cloudfront_price_class}"
  retain_on_delete = true

  default_cache_behavior {
    allowed_methods  = ["HEAD", "DELETE", "POST", "GET", "OPTIONS", "PUT", "PATCH"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "website_bucket_origin"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    # enforce HTTPS by redirecting from HTTP to HTTPS
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # use the ACM managed certificate
  viewer_certificate {
    acm_certificate_arn      = "${data.aws_acm_certificate.public_https_certificate.arn}"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

# route53
data "aws_route53_zone" "experiments" {
  name         = "experiments.georgevella.com."
  private_zone = false
}

# Create a route53 record for the root domain pointing to the root cloudfront dist.
resource "aws_route53_record" "website_route53_record" {
  zone_id = "${data.aws_route53_zone.experiments.zone_id}"
  name    = "${var.domain}"
  type    = "A"

  alias {
    name                   = "${aws_cloudfront_distribution.cdn.domain_name}"
    zone_id                = "Z2FDTNDATAQYW2"       # constant zone-id used for cloudfront distributions (http://docs.aws.amazon.com/general/latest/gr/rande.html)
    evaluate_target_health = false
  }
}
