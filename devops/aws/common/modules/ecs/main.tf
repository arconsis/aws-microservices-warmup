# Set up CloudWatch group and log stream and retain logs for 30 days
resource "aws_cloudwatch_log_group" "this" {
  name              = var.task_definition.aws_logs_group
  retention_in_days = var.logs_retention_in_days

  tags = {
    Name = "${var.task_definition.name}_lg"
  }
}

resource "aws_service_discovery_service" "this" {
  count = var.enable_discovery == false ? 0 : 1
  name  = var.service.name

  dns_config {
    namespace_id = var.dns_namespace_id

    dns_records {
      ttl  = var.discovery_ttl
      type = "A"
    }

    routing_policy = var.discovery_routing_policy
  }
}

data "template_file" "this" {
  template = file("../common/templates/ecs/task.json.tpl")
  vars     = {
    task_name      = var.task_definition.name
    image          = var.task_definition.image
    container_port = var.task_definition.container_port
    host_port      = var.task_definition.host_port
    fargate_cpu    = var.fargate_cpu
    fargate_memory = var.fargate_memory
    aws_region     = var.aws_region
    aws_logs_group = var.task_definition.aws_logs_group
    network_mode   = var.task_definition.network_mode
    env_vars       = jsonencode(var.task_definition.env_vars)
    secret_vars    = jsonencode(var.task_definition.secret_vars)
  }
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.task_definition.family
  execution_role_arn       = var.iam_role_ecs_task_execution_role.arn
  network_mode             = var.task_definition.network_mode
  requires_compatibilities = var.task_compatibilities
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  container_definitions    = data.template_file.this.rendered
}

resource "aws_ecs_service" "this" {
  name            = var.service.name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.service.desired_count
  launch_type     = var.launch_type

  health_check_grace_period_seconds = var.enable_alb == true ? var.health_check_grace_period_seconds : null

  network_configuration {
    security_groups  = var.service_security_groups_ids
    subnets          = var.subnet_ids
    assign_public_ip = var.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = var.enable_alb == false ? [] : [1]
    content {
      target_group_arn = aws_alb_target_group.this[0].arn
      container_name   = var.task_definition.container_name
      container_port   = var.task_definition.container_port
    }
  }

  dynamic "service_registries" {
    for_each = var.enable_discovery == false ? [] : [1]
    content {
      registry_arn   = aws_service_discovery_service.this[0].arn
      container_name = var.task_definition.container_name
    }
  }

  dynamic "ordered_placement_strategy" {
    for_each = var.has_ordered_placement == false ? [] : [1]
    content {
      type  = "binpack"
      field = "memory"
    }
  }

  depends_on = [var.alb_listener, var.iam_role_policy_ecs_task_execution_role]
}

resource "aws_alb_target_group" "this" {
  count = var.enable_alb == true ? 1 : 0

  name        = var.alb.listener.tg
  port        = var.alb.listener.port
  protocol    = var.alb.listener.protocol
  vpc_id      = var.vpc_id
  target_type = var.alb.listener.target_type

  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "3"
    path                = var.task_definition.health_check_path
    unhealthy_threshold = "2"
  }

  depends_on = [var.alb_listener]
}

resource "aws_alb_listener_rule" "this" {
  count = var.enable_alb == true ? 1 : 0

  listener_arn = var.alb.listener.arn
  priority     = var.alb.listener.rule_priority

  action {
    type             = var.alb.listener.rule_type # Redirect all traffic from the ALB to the target group
    target_group_arn = aws_alb_target_group.this[0].arn
  }

  condition {
    path_pattern {
      values = var.alb.listener.tg_paths
    }
  }
}

resource "aws_appautoscaling_target" "this" {
  count              = var.autoscaling_settings != null ? 1 : 0
  max_capacity       = var.autoscaling_settings.max_capacity
  min_capacity       = var.autoscaling_settings.min_capacity
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_policy_cpu" {
  count = try(var.autoscaling_settings.target_cpu_value, null) != null ? 1 : 0

  name               = "${var.autoscaling_settings.autoscaling_name}-scale-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = var.autoscaling_settings.target_cpu_value
    scale_in_cooldown  = var.autoscaling_settings.scale_in_cooldown
    scale_out_cooldown = var.autoscaling_settings.scale_out_cooldown
  }
}

resource "aws_appautoscaling_policy" "ecs_policy_memory" {
  count = try(var.autoscaling_settings.target_memory_value, null) != null ? 1 : 0

  name               = "${var.autoscaling_settings.autoscaling_name}-scale-memory"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = var.autoscaling_settings.target_memory_value
    scale_in_cooldown  = var.autoscaling_settings.scale_in_cooldown
    scale_out_cooldown = var.autoscaling_settings.scale_out_cooldown
  }
}
