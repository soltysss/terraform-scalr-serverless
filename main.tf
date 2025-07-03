terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    scalr = {
      source = "scalr/scalr"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "scalr" {
  hostname = var.scalr_hostname
  token    = var.scalr_token
}


data "aws_availability_zones" "available" {
  state = "available"
}

module "api_gateway" {
  source = "./modules/aws/api-gateway"

  name                   = var.api_gateway_name
  environment            = var.api_gateway_environment
  additional_allowed_ips = module.agent_pool.allowed_ips
  allow_all_ingress      = var.allow_all_ingress
  lambda_invoke_arn      = module.lambda.invoke_arn
  lambda_function_name   = module.lambda.function_name
}

module "networking" {
  source = "./modules/aws/networking"

  name = var.vpc_name
  cidr = "10.0.0.0/16"
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
}

module "lambda" {
  source = "./modules/aws/lambda"

  subnet_ids          = module.networking.public_subnet_ids
  cluster_name        = module.ecs.cluster_name
  task_definition_arn = module.ecs.task_definition_arn
  security_group_id   = module.ecs.security_group_id
  function_name       = var.lambda_function_name
  handler             = var.lambda_handler
  memory_size         = var.lambda_memory_size
  runtime             = var.lambda_runtime
  source_file         = "${path.module}/lamdba_function.py"
  timeout             = var.lambda_timeout
}

module "agent_pool" {
  source = "./modules/scalr/agent-pool"
  scalr_token_sub = var.scalr_token
}

module "ecs" {
  source            = "./modules/aws/ecs"
  vpc_id            = module.networking.vpc_id
  allow_all_ingress = var.allow_all_ingress
  limit_cpu         = var.ecs_limit_cpu
  limit_memory      = var.ecs_limit_memory
  image             = var.ecs_image
  cluster_name      = var.ecs_cluster_name
  task_name         = var.ecs_task_name
  scalr_url = module.agent_pool.scalr_url
  scalr_agent_token = module.agent_pool.agent_token

  security_group_name = var.ecs_security_group_name
}
