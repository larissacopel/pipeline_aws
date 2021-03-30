# Configuracao do provider da AWS
provider "aws" {
  region = "us-east-1"
  access_key = "*"
  secret_key = "*"
}

# Cria uma instancia de IAM
resource "aws_instance" "servidor" {
  ami           = "ami-042e8287309f5df03"
  instance_type = "t3.micro"
  tags = {
    Name = "ubuntu"
  }
}

# Cria um role que sera usado na funcao lambda
resource "aws_iam_role" "captura-lambda-role" {
  name = "captura-lambda-role"
  assume_role_policy = file("arquivos/lambda-role.json")
}

# Cria a politica que sera usada na funcao lambda
resource "aws_iam_role_policy" "captura-lamdba-policy" {
  name = "captura-lambda-policy"
  role = "captura-lambda-role"
  policy = file("arquivos/lambda-policy.json")
  depends_on = [
    aws_iam_role.captura-lambda-role
  ]
}

# Compacta o arquivo .py em um .zip
data "archive_file" "lambda-zip" {
  type        = "zip"
  source_dir = "captura-dados"
  output_path = "lambda/captura_dados.zip"
}

# Cria funcão lambda
resource "aws_lambda_function" "captura-lambda-function" {
  function_name     = "captura-dados"
  filename          = "lambda/captura_dados.zip"
  role              = aws_iam_role.captura-lambda-role.arn
  runtime           = "python3.8"
  handler           = "captura_dados.lambda_handler"
  timeout           = "60"
  publish           = true
}

# Cria um grupo de log para a função de captura
resource "aws_cloudwatch_log_group" "captura-log" {
  name              = "/aws/lambda/captura-dados"
  retention_in_days = 1
}

# Cria um cloudwacth que será usado para a execucao da função lambda
resource "aws_cloudwatch_event_rule" "cloudwatch-rule" {
  name = "agendamento_captura"
  description = "Agendamento responsavel pela execucao da captura dos dados de 5 em 5 minutos"
  schedule_expression = "rate(5 minutes)"
}

# Designa a funcao lambda de captura de dados ao cloudwatch criado
resource "aws_cloudwatch_event_target" "captura-event" {
  target_id = aws_lambda_function.captura-lambda-function.id
  rule      = aws_cloudwatch_event_rule.cloudwatch-rule.name
  arn       = aws_lambda_function.captura-lambda-function.arn
}

# Define o permissionamento da funcao lambda
resource "aws_lambda_permission" "captura-lambda-permission" {
  statement_id = "AllowExecutionFromCloudWatch"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.captura-lambda-function.function_name
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.cloudwatch-rule.arn
}

# Cria o kinesis
resource "aws_kinesis_stream" "kinesis-stream" {
  name = "kinesis-stream"
  shard_count = 1
  retention_period = 24

  shard_level_metrics = [
    "IncomingBytes",
    "OutgoingBytes",
  ]

}

# Cria o bucket 'raw' no S3
resource "aws_s3_bucket" "s3-bucket-raw" {
  bucket = "raw-larissa"
  acl    = "private"
}

# Cria o role do firehose
resource "aws_iam_role" "firehose-role" {
  name = "firehose-role"

  assume_role_policy = file("arquivos/firehose-role.json")
}

# Cria a politica que sera usada no kinesis e no firehose
resource "aws_iam_role_policy" "firehose-policy" {
  name = "firehose-policy"
  role = "firehose-role"
  policy = file("arquivos/firehose-policy.json")
  depends_on = [
    aws_iam_role.firehose-role
  ]
}

# Cria o firehose
resource "aws_kinesis_firehose_delivery_stream" "firehose-stream-raw" {
  name        = "firehose-stream-raw"
  destination = "s3"

  s3_configuration {
    role_arn   = aws_iam_role.firehose-role.arn
    bucket_arn = aws_s3_bucket.s3-bucket-raw.arn
  }

  kinesis_source_configuration {
      kinesis_stream_arn = aws_kinesis_stream.kinesis-stream.arn
      role_arn = aws_iam_role.firehose-role.arn
  }
}

# Compacta o arquivo .py em um .zip
data "archive_file" "processamento-lambda-zip" {
  type        = "zip"
  source_dir = "processamento-dados"
  output_path = "lambda/processamento_dados.zip"
}

# Cria a funcao lambda de processamento dos dados
resource "aws_lambda_function" "processamento-lambda-function" {
  function_name     = "processamento-dados"
  filename          = "lambda/processamento_dados.zip"
  role              = aws_iam_role.captura-lambda-role.arn
  runtime           = "python3.8"
  handler           = "processamento_dados.lambda_handler"
  timeout           = "60"
  publish           = true
}

# Cria um grupo de log para a função de processamento
resource "aws_cloudwatch_log_group" "processamento-log" {
  name              = "/aws/lambda/processamento-dados"
  retention_in_days = 1
}

# Cria o bucket 'cleaned_picpay' no S3
resource "aws_s3_bucket" "s3-bucket-cleaned" {
  bucket = "cleaned-larissa"
  acl    = "private"
}

# Cria o firehose de processsamento
resource "aws_kinesis_firehose_delivery_stream" "firehose-stream-cleaned" {
  name        = "firehose-stream-cleaned"
  destination = "extended_s3"

  # Destino
  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose-role.arn
    bucket_arn = aws_s3_bucket.s3-bucket-cleaned.arn

    processing_configuration {
      enabled = "true"

      processors {
        type = "Lambda"

        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${aws_lambda_function.processamento-lambda-function.arn}:$LATEST"
        }
      }
    }
  }

  # Origem
  kinesis_source_configuration {
      kinesis_stream_arn = aws_kinesis_stream.kinesis-stream.arn
      role_arn = aws_iam_role.firehose-role.arn
  }
}

# Cria um database no Glue
resource "aws_glue_catalog_database" "glue-database" {
  name = "glue-database"
}

# Cria uma tabela no Glue
resource "aws_glue_catalog_table" "glue-table" {
  name               = "cleaned_larissa"
  database_name      = aws_glue_catalog_database.glue-database.name

  storage_descriptor {
    location      = "s3://cleaned-larissa/"

    ser_de_info {
      name                  = "my-stream"
      serialization_library = "org.apache.hadoop.hive.serde2.OpenCSVSerde"
    }

    columns {
      name    = "id"
      type    = "int"
    }
    columns {
      name    = "name"
      type    = "string"
    }
    columns {
      name    = "abv"
      type    = "float"
    }
    columns {
      name    = "ibu"
      type    = "int"
    }
    columns {
      name    = "target_fg"
      type    = "int"
    }
    columns {
      name    = "target_og"
      type    = "int"
    }
    columns {
      name    = "ebc"
      type    = "int"
    }
    columns {
      name    = "srm"
      type    = "int"
    }
    columns {
      name    = "ph"
      type    = "float"
    }
  }
}

# Cria um role que sera usado no crawler
resource "aws_iam_role" "crawler-role" {
  name = "crawler-role"
  assume_role_policy = file("arquivos/crawler-role.json")
}

# Cria a politica que sera usada no crawler
resource "aws_iam_role_policy" "crawler-policy" {
  name = "crawler-policy"
  role = "crawler-role"
  policy = file("arquivos/crawler-policy.json")
  depends_on = [
    aws_iam_role.crawler-role
  ]
}

# Cria o crawler do Glue
resource "aws_glue_crawler" "glue-crawler" {
  database_name = aws_glue_catalog_database.glue-database.name
  name          = "cleaned-crawler"
  role          = aws_iam_role.crawler-role.id

  s3_target {
    path = "s3://cleaned-larissa/"
  }
}

# Cria uma classifier do Glue
resource "aws_glue_classifier" "glue-classifier" {
  name = "glue-classifier"

  csv_classifier {
    allow_single_column    = false
    contains_header        = "ABSENT"
    delimiter              = ","
    disable_value_trimming = false
    header                 = ["id", "name", "abv", "ibu", "target_fg", "target_og", "ebc", "srm", "ph"]
    quote_symbol           = "\""
  }
}