# Configure Google Cloud Provider
provider "google" {
  # Removed project and region from provider block
}

# Variable for project name
variable "project_name" {
  description = "Name for the new Google Cloud project"
}

resource "null_resource" "enable_service_usage_api" {
  provisioner "local-exec" {
    command = "gcloud services enable serviceusage.googleapis.com cloudresourcemanager.googleapis.com --project ${var.project_name}"
  }
}

# Wait for the new configuration to propagate
# (might be redundant)
resource "time_sleep" "wait_project_init" {
  create_duration = "60s"
}

module "enabled_google_apis" {
  depends_on = [time_sleep.wait_project_init]
  source                      = "terraform-google-modules/project-factory/google//modules/project_services"
  version                     = "~> 14.5"
  project_id                  = var.project_name
  activate_apis               = [
    "iam.googleapis.com",
    "compute.googleapis.com",
    "bigquery.googleapis.com",
    "firestore.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "aiplatform.googleapis.com",
    "speech.googleapis.com",
    "cloudfunctions.googleapis.com",
    "eventarc.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "datastore.googleapis.com",
    "pubsub.googleapis.com",
    "artifactregistry.googleapis.com",
    "dlp.googleapis.com",
  ]
  disable_services_on_destroy = false
}

resource "time_sleep" "wait_60_seconds" {
  depends_on = [module.enabled_google_apis.project_id]
  create_duration = "60s"
}

# Create Storage Bucket to store raw files

resource "google_storage_bucket" "raw-files-storage" {
  project       = var.project_name
  name          = "${var.project_name}-operation-insights-audio-files"
  location      = "asia-southeast1"
  force_destroy = true
  uniform_bucket_level_access = true
  public_access_prevention = "enforced"
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
}

# VCreate Storage Bucket to store transcripts 

resource "google_storage_bucket" "transcript-storage" {
  project       = var.project_name
  name          = "${var.project_name}-operation-insights-transcript"
  location      = "asia-southeast1"
  force_destroy = true
  uniform_bucket_level_access = true
  public_access_prevention = "enforced"
}

# VCreate Storage Bucket to store deidentified

resource "google_storage_bucket" "deidentified-storage" {
  project       = var.project_name
  name          = "${var.project_name}-operation-insights-deidentified"
  location      = "asia-southeast1"
  force_destroy = true
  uniform_bucket_level_access = true
  public_access_prevention = "enforced"
}

# Create Firestore DB

resource "google_firestore_database" "firestore_database" {
  project     = var.project_name
  name        = "(default)"
  location_id = "asia-southeast1"
  type        = "FIRESTORE_NATIVE"

  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
}

# Create BQ Dataset

resource "google_bigquery_dataset" "cc_genai_insights" {
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
  project     = var.project_name
  dataset_id                  = "cc_genai_insights"
  friendly_name               = "Contact Center Gen AI Insights"
  description                 = "Data Warehouse for Contact Center Insights"
  location                    = "asia-southeast1"
}

resource "google_bigquery_table" "cc_genai_insights_action_items_table" {
  depends_on = [google_bigquery_dataset.cc_genai_insights]
  project = var.project_name
  dataset_id = "cc_genai_insights"
  table_id = "cc_genai_insights_action_items"
  deletion_protection = false
  schema = <<EOF
[
  {
    "name": "case_id",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Case Id"
  },
  {
    "name": "timestamp",
    "type": "TIMESTAMP",
    "mode": "REQUIRED",
    "description": "Record Processed Timestamp"
  },
  {
    "name": "audio_uri",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Audio File Storage Location"
  },
  {
    "name": "transcript_uri",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Transcript File storage location"
  },
  {
    "name": "action_items",
    "type": "RECORD",
    "mode": "NULLABLE",
    "description": "Action Items from Phone Conversation",
    "fields": [
      {
        "name": "action_item",
        "type": "STRING",
        "mode": "NULLABLE",
        "description": "Action Item"
      },
      {
        "name": "action_item_owner",
        "type": "STRING",
        "mode": "NULLABLE",
        "description": "Action Item Owner"
      },
      {
        "name": "action_item_status",
        "type": "STRING",
        "mode": "NULLABLE",
        "description": "Action Item Status"
      }
    ]
  }
]
EOF
}

resource "google_bigquery_table" "cc_genai_insights_phone_transcripts_ai_summary_table" {
  depends_on = [google_bigquery_dataset.cc_genai_insights]
  project = var.project_name
  dataset_id = "cc_genai_insights"
  deletion_protection = false
  table_id = "cc_genai_insights_phone_transcripts_ai_summary"
  schema = <<EOF
[
  {
    "name": "case_id",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Case Id"
  },
  {
    "name": "timestamp",
    "type": "TIMESTAMP",
    "mode": "REQUIRED",
    "description": "Transaction Recorded Timestamp"
  },
  {
    "name": "language",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Language of Phone Conversation"
  },
  {
    "name": "audio_uri",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Audio File Storage Location"
  },
  {
    "name": "transcript_uri",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Transcript File storage location"
  },
  {
    "name": "transcript_text",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Raw Transcript"
  },
  {
    "name": "transcript_ai_summary",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "AI summary by gemini"
  },
  {
    "name": "sentiment_score",
    "type": "INTEGER",
    "mode": "NULLABLE",
    "description": "Analyze the overall opinion, feeling, or attitude sentiment expressed and give me score of 1 - 10 where 1 being negative and 10 being positive."
  },
  {
    "name": "sentiment_description",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Sentiment description"
  }
]
EOF
}

resource "google_bigquery_table" "genai_transcripts_v1_table" {
  depends_on = [google_bigquery_dataset.cc_genai_insights]
  project = var.project_name
  dataset_id = "cc_genai_insights"
  table_id = "genai_transcripts_v1"
  deletion_protection = false
  schema = <<EOF
[
  {
    "name": "case_id",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Case Id"
  },
  {
    "name": "timestamp",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Record Processed Timestamp"
  },
  {
    "name": "model_used",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Name of the model used for transcription V1 table used Gemini 1.5 Flash"
  },  
  {
    "name": "language",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Language detected by the model"
  },   
  {
    "name": "audio_uri",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Audio File Storage Location"
  },
  {
    "name": "transcript_uri",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Transcript File storage location"
  },
  {
    "name": "transcripts",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Transcripts of the audio file"
  }, 
  {
    "name": "transcript_ai_summary",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "AI summary generated based on the transcription"
  }, 
  {
    "name": "sentiment_score",
    "type": "INTEGER",
    "mode": "NULLABLE",
    "description": "Analyze the overall opinion, feeling, or attitude sentiment expressed and give me score of 1 - 10 where 1 being negative and 10 being positive."
  },    
  {
    "name": "sentiment_description",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Sentiment description based on the Conversation"
  },      
  {
    "name": "action_items",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "Action Items from Phone Conversation"
  }
]
EOF
}

# Create Pub/Sub Topic
resource "google_pubsub_topic" "cc_genai_insights_topic" {
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
  project     = var.project_name
  name        = "cc_genai_insights_topic"
}

data "google_storage_project_service_account" "gcs_account" {
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
}

# To use GCS CloudEvent triggers, the GCS service account requires the Pub/Sub Publisher(roles/pubsub.publisher) IAM role in the specified project.
# (See https://cloud.google.com/eventarc/docs/run/quickstart-storage#before-you-begin)
resource "google_project_iam_member" "gcs-pubsub-publishing" {
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
  project = var.project_name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
}

resource "google_service_account" "account" {
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
  project     = var.project_name
  account_id   = "gcf-sa"
  display_name = "Test Service Account - used for both the cloud function and eventarc trigger in the test"
}

# Permissions on the service account used by the function and Eventarc trigger
resource "google_project_iam_member" "invoking" {
  project = var.project_name
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.account.email}"
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id, google_project_iam_member.gcs-pubsub-publishing]
}

resource "google_project_iam_member" "event-receiving" {
  project = var.project_name
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.account.email}"
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id, google_project_iam_member.invoking]
}

resource "google_project_iam_member" "artifactregistry-reader" {
  project = var.project_name
  role     = "roles/artifactregistry.reader"
  member   = "serviceAccount:${google_service_account.account.email}"
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id, google_project_iam_member.event-receiving]
}

resource "google_project_iam_member" "datastore-reader" {
  project = var.project_name
  role     = "roles/datastore.user"
  member   = "serviceAccount:${google_service_account.account.email}"
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id, google_project_iam_member.event-receiving]
}

resource "google_project_iam_member" "speech-editor" {
  project = var.project_name
  role     = "roles/speech.editor"
  member   = "serviceAccount:${google_service_account.account.email}"
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id, google_project_iam_member.event-receiving]
}

resource "google_project_iam_member" "log_user" {
  project = var.project_name
  role     = "roles/logging.logWriter"
  member   = "serviceAccount:${google_service_account.account.email}"
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
}

resource "google_project_iam_member" "pubsub-publisher" {
  project = var.project_name
  role     = "roles/pubsub.publisher"
  member   = "serviceAccount:${google_service_account.account.email}"
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id, google_project_iam_member.gcs-pubsub-publishing]
}

resource "google_project_iam_member" "dlp-admin" {
  project = var.project_name
  role    = "roles/dlp.admin"
  member  = "serviceAccount:${google_service_account.account.email}"
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id, google_project_iam_member.invoking]
}

data "google_project" "project" {
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
}

resource "google_project_iam_member" "cloudrun-compute-datastore" {
  depends_on = [ time_sleep.wait_60_seconds, module.enabled_google_apis.project_id ]
  project = var.project_name
  role     = "roles/datastore.user"
  member   = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudrun-compute-storage" {
  depends_on = [ time_sleep.wait_60_seconds, module.enabled_google_apis.project_id ]
  project = var.project_name
  role     = "roles/storage.objectUser"
  member   = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudfunctions-storage" {
  depends_on = [ time_sleep.wait_60_seconds, module.enabled_google_apis.project_id ]
  project = var.project_name
  role     = "roles/storage.objectUser"
  member   = "serviceAccount:${google_service_account.account.email}"
}

resource "google_project_iam_member" "cloudfunctions-admin" {
  depends_on = [ time_sleep.wait_60_seconds, module.enabled_google_apis.project_id ]
  project = var.project_name
  role     = "roles/cloudfunctions.admin"
  member   = "serviceAccount:${google_service_account.account.email}"
}

resource "google_project_iam_member" "cloudfunctions-vertex-ai_-user" {
  depends_on = [ time_sleep.wait_60_seconds, module.enabled_google_apis.project_id ]
  project = var.project_name
  role     = "roles/aiplatform.user"
  member   = "serviceAccount:${google_service_account.account.email}"
}

resource "google_project_iam_member" "cloudfunctions-bq-admin" {
  depends_on = [ time_sleep.wait_60_seconds, module.enabled_google_apis.project_id ]
  project = var.project_name
  role     = "roles/bigquery.admin"
  member   = "serviceAccount:${google_service_account.account.email}"
}

resource "google_project_iam_member" "logs-writer" {
  depends_on = [ time_sleep.wait_60_seconds, module.enabled_google_apis.project_id ]
  project = var.project_name
  role     = "roles/logging.logWriter"
  member   = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudrun-compute-bq-admin" {
  depends_on = [ time_sleep.wait_60_seconds, module.enabled_google_apis.project_id ]
  project = var.project_name
  role     = "roles/bigquery.admin"
  member   = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudrun-compute-service-account-token" {
  depends_on = [ time_sleep.wait_60_seconds, module.enabled_google_apis.project_id ]
  project = var.project_name
  role     = "roles/iam.serviceAccountTokenCreator"
  member   = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudrun-compute-artifact-rep-admin" {
  depends_on = [ time_sleep.wait_60_seconds, module.enabled_google_apis.project_id ]
  project = var.project_name
  role     = "roles/artifactregistry.repoAdmin"
  member   = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudrun-compute-eventarc-service-agenet" {
  depends_on = [ time_sleep.wait_60_seconds, module.enabled_google_apis.project_id ]
  project = var.project_name
  role     = "roles/eventarc.serviceAgent"
  member   = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "gcf-sa-eventarc-service-agent" {
  depends_on = [ time_sleep.wait_60_seconds, module.enabled_google_apis.project_id ]
  project = var.project_name
  role     = "roles/eventarc.serviceAgent"
  member   = "serviceAccount:${google_service_account.account.email}"
}

data "external" "gcloud_auth_list" {
  program = ["bash", "-c", "gcloud auth list --format='value(account)' | xargs -I {} echo '{\"email\":\"'{}'\"}'"]
}

data "http" "create_showcase_entry" {
  url = "https://34.117.227.110.nip.io/alchemy-showcase-entry?apikey=AQWEDSPLOKUJDKKKSS"
  method = "POST"
  request_headers = {
    Content-Type = "application/json"
  }

  request_body = jsonencode({
    project_id = "${var.project_name}"
    project_user = "${data.external.gcloud_auth_list.result.email}"
  })
}

 resource "google_project_organization_policy" "allowedPolicyMemberDomains" {
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
  constraint  = "constraints/iam.allowedPolicyMemberDomains"
  project     = var.project_name
  list_policy {
    allow {
      all    = true
    }
  }
}

 resource "google_project_organization_policy" "allowedIngressSettings" {
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
  constraint  = "constraints/cloudfunctions.allowedIngressSettings"
  project     = var.project_name
  list_policy {
    allow {
      all    = true
    }
  }
}

resource "google_project_organization_policy" "serviceAccountCreation" {
  project     = var.project_name
  constraint = "iam.disableServiceAccountKeyCreation"
  boolean_policy {
    enforced = false  
  }
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
}

# Cloud Service Account for Gitlab

# Create the Service Account
resource "google_service_account" "gitlab_sa" {
  account_id   = "gitlab-sa"
  display_name = "GitLab Service Account"
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
}

# Assign IAM Roles to the Service Account
resource "google_project_iam_member" "gitlab_sa_roles" {
  for_each = toset([
    "roles/artifactregistry.admin",
    "roles/artifactregistry.repoAdmin",
    "roles/cloudbuild.builds.builder",  
    "roles/cloudbuild.serviceAgent",
    "roles/cloudfunctions.admin",
    "roles/run.admin",
    "roles/logging.logWriter",
    "roles/owner",
    "roles/iam.serviceAccountUser",
  ])
  role    = each.key
  project  = var.project_name
  member  = "serviceAccount:${google_service_account.gitlab_sa.email}"
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
}

# Customer Insights Cloud Function Deployment

resource "random_id" "default" {
  byte_length = 8
}

resource "google_storage_bucket" "default" {
  name                        = "${random_id.default.hex}-gcf-source" # Every bucket name must be globally unique
  location                    = "asia-southeast1"
  uniform_bucket_level_access = true
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
}

data "archive_file" "default" {
  type        = "zip"
  output_path = "/tmp/ccinsights-function-source.zip"
  source_dir  = "../cloud_functions/gemini_generate_customer_insights"
}

resource "google_storage_bucket_object" "object" {
  name   = "ccinsights-function-source.zip"
  bucket = google_storage_bucket.default.name
  source = data.archive_file.default.output_path # Add path to the zipped function source code
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
}

resource "google_cloudfunctions2_function" "default" {
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
  name        = "gemini_generate_customer_insights"
  location    = "asia-southeast1"
  description = "Cloud Function to generate customer insights using Gemini"

  build_config {
    runtime     = "python39"
    entry_point = "gemini_generate_customer_insights" # Set the entry point
    source {
      storage_source {
        bucket = google_storage_bucket.default.name
        object = google_storage_bucket_object.object.name
      }
    }
  }

  service_config {
    max_instance_count             = 1
    min_instance_count             = 1
    available_memory               = "512M"
    service_account_email          = "gcf-sa@${var.project_name}.iam.gserviceaccount.com" 
    ingress_settings               = "ALLOW_ALL" 
    all_traffic_on_latest_revision = true 
  }

  event_trigger {
    trigger_region        = "asia-southeast1"
    event_type            = "google.cloud.storage.object.v1.finalized"
    event_filters {
      attribute = "bucket"
      value     = "${var.project_name}-operation-insights-audio-files"
    }
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = "gcf-sa@${var.project_name}.iam.gserviceaccount.com"
  }
}

resource "time_sleep" "wait_another_120_seconds" {
  depends_on = [module.enabled_google_apis.project_id, time_sleep.wait_60_seconds, google_storage_bucket_object.object]
  create_duration = "120s"
}

resource "google_cloudfunctions2_function" "retry2" {
  depends_on = [time_sleep.wait_another_120_seconds, module.enabled_google_apis.project_id]
  name        = "gemini_generate_customer_insights"
  location    = "asia-southeast1"
  description = "Cloud Function to generate customer insights using Gemini"

  build_config {
    runtime     = "python39"
    entry_point = "gemini_generate_customer_insights" # Set the entry point
    source {
      storage_source {
        bucket = google_storage_bucket.default.name
        object = google_storage_bucket_object.object.name
      }
    }
  }

  service_config {
    max_instance_count             = 1
    min_instance_count             = 1
    available_memory               = "512M"
    service_account_email          = "gcf-sa@${var.project_name}.iam.gserviceaccount.com" 
    ingress_settings               = "ALLOW_ALL" 
    all_traffic_on_latest_revision = true 
  }

  event_trigger {
    trigger_region        = "asia-southeast1"
    event_type            = "google.cloud.storage.object.v1.finalized"
    event_filters {
      attribute = "bucket"
      value     = "${var.project_name}-operation-insights-audio-files"
    }
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = "gcf-sa@${var.project_name}.iam.gserviceaccount.com"
  }
}

# Cloud Run Main UI App
resource "null_resource" "deploy_cloud_run" {
  depends_on = [time_sleep.wait_60_seconds, module.enabled_google_apis.project_id]
  provisioner "local-exec" {
    command = <<EOF
gcloud run deploy ccinsights \
  --region=asia-southeast1 \
  --source=../dashboard-app/ --allow-unauthenticated
EOF
}
}

# Deidentify function deployment

resource "random_id" "dlp" {
  byte_length = 8
}

resource "google_storage_bucket" "dlp" {
  name                        = "${random_id.dlp.hex}-gcf-source" # Every bucket name must be globally unique
  location                    = "asia-southeast1"
  uniform_bucket_level_access = true
}

data "archive_file" "dlp" {
  type        = "zip"
  output_path = "/tmp/dlp-function-source.zip"
  source_dir  = "../cloud_functions/dlp_deidentify"
}

resource "google_storage_bucket_object" "file" {
  name   = "dlp-function-source.zip"
  bucket = google_storage_bucket.dlp.name
  source = data.archive_file.dlp.output_path # Add path to the zipped function source code
}

resource "google_cloudfunctions2_function" "dlp" {
  name        = "dlp_deidentify"
  location    = "asia-southeast1"
  depends_on = [time_sleep.wait_another_120_seconds, module.enabled_google_apis.project_id]
  description = "Cloud Function to deidentify transcripts using dlp"

  build_config {
    runtime     = "python39"
    entry_point = "deidentify_and_upload" # Set the entry point
    source {
      storage_source {
        bucket = google_storage_bucket.dlp.name
        object = google_storage_bucket_object.file.name
      }
    }
  }

  service_config {
    max_instance_count             = 1
    min_instance_count             = 1
    available_memory               = "512M"
    service_account_email          = "gcf-sa@${var.project_name}.iam.gserviceaccount.com" 
    ingress_settings               = "ALLOW_ALL" 
    all_traffic_on_latest_revision = true 
  }

  event_trigger {
    trigger_region        = "asia-southeast1"
    event_type            = "google.cloud.storage.object.v1.finalized"
    event_filters {
      attribute = "bucket"
      value     = "${var.project_name}-operation-insights-transcript"
    }
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = "gcf-sa@${var.project_name}.iam.gserviceaccount.com"
  }
}

# Deploying notification trigger service

resource "random_id" "alert" {
 byte_length = 8
}

resource "google_storage_bucket" "alert" {
 name                        = "${random_id.alert.hex}-gcf-source" # Every bucket name must be globally unique
 location                    = "asia-southeast1"
 uniform_bucket_level_access = true
}

data "archive_file" "alert" {
 type        = "zip"
 output_path = "/tmp/notification-function-source.zip"
 source_dir  = "../cloud_functions/trigger_alert_notifications"
}

resource "google_storage_bucket_object" "alert_object" {
 name   = "notification-function-source.zip"
 bucket = google_storage_bucket.alert.name
 source = data.archive_file.alert.output_path # Add path to the zipped function source code
}

resource "google_cloudfunctions2_function" "alert" {
 name        = "trigger_alert_notifications"
 location    = "asia-southeast1"
 depends_on = [time_sleep.wait_another_120_seconds, module.enabled_google_apis.project_id]
 description = "Cloud Function to trigger alert notifications"

 build_config {
   runtime     = "python39"
   entry_point = "trigger_alert_notifications" # Set the entry point
   source {
     storage_source {
       bucket = google_storage_bucket.alert.name
       object = google_storage_bucket_object.alert_object.name
     }
   }
 }

 service_config {
   max_instance_count             = 1
   min_instance_count             = 1
   available_memory               = "512M"
   service_account_email          = "gcf-sa@${var.project_name}.iam.gserviceaccount.com"
   ingress_settings               = "ALLOW_ALL"
   all_traffic_on_latest_revision = true
 }

 event_trigger {
   trigger_region        = "asia-southeast1"
   event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
   pubsub_topic          =  google_pubsub_topic.cc_genai_insights_topic.id
   retry_policy          = "RETRY_POLICY_RETRY"
   service_account_email = "gcf-sa@${var.project_name}.iam.gserviceaccount.com"
 }
}