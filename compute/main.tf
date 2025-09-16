
# Web Application Load Balancer
resource "aws_lb" "web" {
  name               = "${var.project_name}-web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [data.terraform_remote_state.network.outputs.frontend_alb_sg_id]
  subnets            = [
    data.terraform_remote_state.network.outputs.public_subnet_1a_id,
    data.terraform_remote_state.network.outputs.public_subnet_1b_id,
    data.terraform_remote_state.network.outputs.public_subnet_1c_id
  ]

  enable_deletion_protection = false

  tags = {
    Name        = "${var.project_name}-web-alb"
    Environment = var.environment
  }
}

# Web Application Load Balancer Target Group
resource "aws_lb_target_group" "web" {
  name     = "${var.project_name}-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.terraform_remote_state.network.outputs.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project_name}-web-tg"
    Environment = var.environment
  }
}

# Web Application Load Balancer Listener
resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# Web Launch Template
resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-web-"
  image_id      = local.web_ami_id
  instance_type = var.web_instance_type
  key_name      = var.key_name  # Just use the key name directly

  network_interfaces {
    associate_public_ip_address = false
    security_groups            = [data.terraform_remote_state.network.outputs.web_sg_id]
  }


  user_data = base64encode(templatefile("${path.module}/web_user_data.sh", {
    project_name = var.project_name
    app_alb_dns  = aws_lb.app.dns_name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-web"
      Environment = var.environment
    }
  }
}

# Web Auto Scaling Group
resource "aws_autoscaling_group" "web" {
  name                = "${var.project_name}-web-asg"
  vpc_zone_identifier = [
    data.terraform_remote_state.network.outputs.web_private_subnet_1a_id,
    data.terraform_remote_state.network.outputs.web_private_subnet_1b_id,
    data.terraform_remote_state.network.outputs.web_private_subnet_1c_id
  ]
  desired_capacity    = var.web_desired_capacity
  max_size            = var.web_max_size
  min_size            = var.web_min_size

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.web.arn]

  tag {
    key                 = "Name"
    value               = "${var.project_name}-web"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}

# App Application Load Balancer
resource "aws_lb" "app" {
  name               = "${var.project_name}-app-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [data.terraform_remote_state.network.outputs.backend_alb_sg_id]
  subnets            = [
    data.terraform_remote_state.network.outputs.app_private_subnet_1a_id,
    data.terraform_remote_state.network.outputs.app_private_subnet_1b_id,
    data.terraform_remote_state.network.outputs.app_private_subnet_1c_id
  ]

  enable_deletion_protection = false

  tags = {
    Name        = "${var.project_name}-app-alb"
    Environment = var.environment
  }
}

# App Target Group
resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.terraform_remote_state.network.outputs.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.project_name}-app-tg"
    Environment = var.environment
  }
}

# App Listener
resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# App Launch Template
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-app-"
  image_id      = local.app_ami_id
  instance_type = var.app_instance_type
  key_name      = var.key_name  # Just use the key name directly

  network_interfaces {
    associate_public_ip_address = false
    security_groups            = [data.terraform_remote_state.network.outputs.app_sg_id]
  }

  user_data = base64encode(templatefile("${path.module}/app_user_data.sh", {
    project_name = var.project_name
    db_host      = data.terraform_remote_state.database.outputs.rds_address
    db_username  = data.terraform_remote_state.database.outputs.rds_username
    db_password  = var.db_password  # Use the variable directly
    environment  = var.environment
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-app"
      Environment = var.environment
    }
  }
}

# App Auto Scaling Group
resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-app-asg"
  vpc_zone_identifier = [
    data.terraform_remote_state.network.outputs.app_private_subnet_1a_id,
    data.terraform_remote_state.network.outputs.app_private_subnet_1b_id,
    data.terraform_remote_state.network.outputs.app_private_subnet_1c_id
  ]
  desired_capacity    = var.app_desired_capacity
  max_size            = var.app_max_size
  min_size            = var.app_min_size

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app.arn]

  tag {
    key                 = "Name"
    value               = "${var.project_name}-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}

