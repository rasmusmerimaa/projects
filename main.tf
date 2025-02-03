terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {
  host = "npipe:////./pipe/podman-machine-default"
}

##########################
# Create a shared network
##########################
resource "docker_network" "airflow_network" {
  name = "airflow_network"
}

##########################
# Postgres Service
##########################
resource "docker_volume" "postgres_data" {
  name = "postgres_db_volume"
}

resource "docker_container" "postgres" {
  name  = "postgres"
  image = "postgres:13"

  env = [
    "POSTGRES_USER=airflow",
    "POSTGRES_PASSWORD=airflow",
    "POSTGRES_DB=airflow",
  ]

  ports {
    internal = 5432
    external = 5432
  }

  volumes {
    container_path = "/var/lib/postgresql/data"
    volume_name    = docker_volume.postgres_data.name
  }

  healthcheck {
    test         = ["CMD", "pg_isready", "-U", "airflow"]
    interval     = "10s"
    timeout      = "10s"
    retries      = 5
    start_period = "5s"
  }

  networks_advanced {
    name = docker_network.airflow_network.name
  }

  restart = "always"
}

##########################
# Redis Service
##########################
resource "docker_container" "redis" {
  name  = "redis"
  image = "redis:7.2-bookworm"

  healthcheck {
    test         = ["CMD", "redis-cli", "ping"]
    interval     = "10s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }

  networks_advanced {
    name = docker_network.airflow_network.name
  }

  restart = "always"
}

##########################
# Airflow Initialization Service
##########################
resource "docker_container" "airflow_init" {
  depends_on = [docker_container.postgres, docker_container.redis]
  name       = "airflow-init"
  image      = "apache/airflow:2.10.4"

  entrypoint = ["/bin/bash"]
  command = [
    "-c",
    "airflow db upgrade && airflow users create --username airflow --password airflow --firstname Airflow --lastname Admin --role Admin --email airflow@example.com"
  ]

  env = [
    "AIRFLOW__CORE__EXECUTOR=CeleryExecutor",
    "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@postgres/airflow",
    "AIRFLOW__CELERY__RESULT_BACKEND=db+postgresql://airflow:airflow@postgres/airflow",
    "AIRFLOW__CELERY__BROKER_URL=redis://redis:6379/0",
    "AIRFLOW__CORE__FERNET_KEY=some_random_key", // Replace with a secure key in production
    "AIRFLOW__CORE__LOAD_EXAMPLES=true",
    "AIRFLOW_UID=50000",
    "AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=false"
  ]

  user = "0:0"

  networks_advanced {
    name = docker_network.airflow_network.name
  }

  restart = "no"
}

##########################
# Airflow Webserver Service
##########################
resource "docker_container" "airflow_webserver" {
  depends_on = [docker_container.airflow_init]
  name       = "airflow-webserver"
  image      = "apache/airflow:2.10.4"
  command    = ["webserver"]

  ports {
    internal = 8080
    external = 8000
  }

  env = [
    "AIRFLOW__CORE__EXECUTOR=CeleryExecutor",
    "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@postgres/airflow",
    "AIRFLOW__CELERY__RESULT_BACKEND=db+postgresql://airflow:airflow@postgres/airflow",
    "AIRFLOW__CELERY__BROKER_URL=redis://redis:6379/0",
    "AIRFLOW__CORE__FERNET_KEY=some_random_key", // Replace with your secure key
    "AIRFLOW__CORE__LOAD_EXAMPLES=true",
    "AIRFLOW_UID=50000",
    "_PIP_ADDITIONAL_REQUIREMENTS=psutil",
    "AIRFLOW__SMTP__SMTP_HOST=smtp.gmail.com",
    "AIRFLOW__SMTP__SMTP_PORT=587",
    "AIRFLOW__SMTP__SMTP_STARTTLS=True",
    "AIRFLOW__SMTP__SMTP_USER=your_email@gmail.com",
    "AIRFLOW__SMTP__SMTP_PASSWORD=your_app_password",
    "AIRFLOW__SMTP__SMTP_MAIL_FROM=your_email@gmail.com",
    "AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=false"
  ]

  volumes {
    host_path      = abspath("${path.module}/dags")
    container_path = "/opt/airflow/dags"
  }

  user = "50000:0"

  networks_advanced {
    name = docker_network.airflow_network.name
  }

  healthcheck {
    test         = ["CMD", "curl", "--fail", "http://localhost:8080/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }

  restart = "always"
}

##########################
# Airflow Scheduler Service
##########################
resource "docker_container" "airflow_scheduler" {
  depends_on = [docker_container.airflow_init]
  name       = "airflow-scheduler"
  image      = "apache/airflow:2.10.4"
  command    = ["scheduler"]

  env = [
    "AIRFLOW__CORE__EXECUTOR=CeleryExecutor",
    "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@postgres/airflow",
    "AIRFLOW__CELERY__RESULT_BACKEND=db+postgresql://airflow:airflow@postgres/airflow",
    "AIRFLOW__CELERY__BROKER_URL=redis://redis:6379/0",
    "AIRFLOW__CORE__FERNET_KEY=some_random_key",
    "AIRFLOW__CORE__LOAD_EXAMPLES=true",
    "AIRFLOW_UID=50000",
    "_PIP_ADDITIONAL_REQUIREMENTS=psutil",
    "AIRFLOW__SMTP__SMTP_HOST=smtp.gmail.com",
    "AIRFLOW__SMTP__SMTP_PORT=587",
    "AIRFLOW__SMTP__SMTP_STARTTLS=True",
    "AIRFLOW__SMTP__SMTP_USER=your_email@gmail.com",
    "AIRFLOW__SMTP__SMTP_PASSWORD=your_app_password",
    "AIRFLOW__SMTP__SMTP_MAIL_FROM=your_email@gmail.com",
    "AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=false"
  ]

  volumes {
    host_path      = abspath("${path.module}/dags")
    container_path = "/opt/airflow/dags"
  }

  networks_advanced {
    name = docker_network.airflow_network.name
  }

  restart = "always"
}

##########################
# Airflow Triggerer Service
##########################
resource "docker_container" "airflow_triggerer" {
  depends_on = [docker_container.airflow_init]
  name       = "airflow-triggerer"
  image      = "apache/airflow:2.10.4"
  command    = ["triggerer"]

  env = [
    "AIRFLOW__CORE__EXECUTOR=CeleryExecutor",
    "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://airflow:airflow@postgres/airflow",
    "AIRFLOW__CELERY__RESULT_BACKEND=db+postgresql://airflow:airflow@postgres/airflow",
    "AIRFLOW__CELERY__BROKER_URL=redis://redis:6379/0",
    "AIRFLOW__CORE__FERNET_KEY=some_random_key",
    "AIRFLOW__CORE__LOAD_EXAMPLES=true",
    "AIRFLOW_UID=50000",
    "_PIP_ADDITIONAL_REQUIREMENTS=psutil",
    "AIRFLOW__SMTP__SMTP_HOST=smtp.gmail.com",
    "AIRFLOW__SMTP__SMTP_PORT=587",
    "AIRFLOW__SMTP__SMTP_STARTTLS=True",
    "AIRFLOW__SMTP__SMTP_USER=your_email@gmail.com",
    "AIRFLOW__SMTP__SMTP_PASSWORD=your_app_password",
    "AIRFLOW__SMTP__SMTP_MAIL_FROM=your_email@gmail.com",
    "AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=false"
  ]

  volumes {
    host_path      = abspath("${path.module}/dags")
    container_path = "/opt/airflow/dags"
  }

  networks_advanced {
    name = docker_network.airflow_network.name
  }

  restart = "always"
}
