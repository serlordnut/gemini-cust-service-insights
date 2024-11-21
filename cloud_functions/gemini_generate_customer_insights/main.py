import functions_framework
from google.cloud import firestore
from google.cloud import storage
from google.cloud import bigquery
from google.cloud import logging
from google.api_core.exceptions import NotFound

from google.cloud import pubsub_v1
import os
import textwrap
import datetime
import base64
import json
import re
import vertexai
from vertexai.preview.generative_models import GenerativeModel, Part, FinishReason
import vertexai.preview.generative_models as generative_models
import urllib.request
from datetime import datetime
from json import dumps,loads
TOPIC_ID = "cc_genai_insights_topic"

@functions_framework.cloud_event
def gemini_generate_customer_insights(cloud_event):
    # CloudEvent data is a dictionary
    data = cloud_event.data

    # Get the Cloud Storage bucket and file name from the CloudEvent data
    bucket_name = data["bucket"]
    file_name = data["name"]
    gcs_uri = f"gs://{bucket_name}/{file_name}"

    log_client = logging.Client()
    logger = log_client.logger("cc_insights_log")

    # log the bucket and file name to the function logs
    logger.log_text(f"File {file_name} uploaded to bucket {bucket_name}.",severity="INFO")

    url = "http://metadata.google.internal/computeMetadata/v1/project/project-id"
    req = urllib.request.Request(url)
    req.add_header("Metadata-Flavor", "Google")
    project_id = urllib.request.urlopen(req).read().decode()

    logger.log_text(f"Project ID: {project_id}",severity="INFO")

    # Query the Firestore collection for the case id
    db = firestore.Client()
    collection_ref = db.collection("audio-files-metadata")
    query = collection_ref.where("gcsUri", "==", gcs_uri)
    results = list(query.stream())
    # If the case id is found, print the case id to the function logs
    if results:
        caseid = results[0].get("caseid")
        logger.log_text(f"Case id: {caseid}",severity="INFO")
        logger.log_text(f"Case id: {gcs_uri}",severity="INFO")
        generate(caseid, gcs_uri, project_id)        
    else:
        logger.log_text("Case id not found.",severity="INFO")

def generate(caseid, audioUri, project_id):
    log_client = logging.Client()
    logger = log_client.logger("cc_insights_log")
    logger.log_text(f"Project ID: {project_id}",severity="INFO")
    logger.log_text(f"Audio Uri: {audioUri}",severity="INFO")
    modelname = "gemini-1.5-flash-001"
    vertexai.init(project=project_id, location="asia-southeast1")
    model = GenerativeModel(modelname)

    audio_input = Part.from_uri(
        mime_type="audio/wav",
        uri=audioUri)

    generation_config = {
    "max_output_tokens": 8192,
    "temperature": 1,
    "top_p": 0.95,
    }

    safety_settings = {
        generative_models.HarmCategory.HARM_CATEGORY_HATE_SPEECH: generative_models.HarmBlockThreshold.BLOCK_ONLY_HIGH,
        generative_models.HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: generative_models.HarmBlockThreshold.BLOCK_ONLY_HIGH,
        generative_models.HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: generative_models.HarmBlockThreshold.BLOCK_ONLY_HIGH,
        generative_models.HarmCategory.HARM_CATEGORY_HARASSMENT: generative_models.HarmBlockThreshold.BLOCK_ONLY_HIGH,
    }
    
    responses = model.generate_content(
      [audio_input, textwrap.dedent(""" Audio is the conversation between  Agent and  Customer.

      <INSTRUCTIONS>
        1. Generate raw transcript with details of speaker (Agent or Customer), text, timestamp.
        2. Generate detailed summary of the conversation.
        3. Generate sentiment_score between 1 to 10 where 1 being extremely unsatisfied and 10 being highly satisfied.
        4. Generate sentiment description.
        5. Generate action items with details of owner of action of item (Agent or Customer), Action Item Status, Action Item Description.
        6. Make sure output is a valid json format, and must be in the same language as that of transcript.
      </INSTRUCTIONS>
      <EXAMPLES>
      <Output>
      {
        "raw_transcript": [
          {
            "speaker": "Agent",
            "text": "We are connecting you to customer",
            "timestamp": "0:00"
          },
          {
            "speaker": "Agent",
            "text": "Hello",
            "timestamp": "0:08"
          },
          {
            "speaker": "Customer",
            "text": "Hello",
            "timestamp": "0:08"
          },
          {
            "speaker": "Agent",
            "text": "Hi good eve",
            "timestamp": "0:09"
          }
        ],
        "detailed_summary": "The agent confirmed an inspection appointment with the customer for December 22nd at 12pm at Harbortown Jeep. The agent reminded the customer to bring their car grant, stating it is mandatory for the inspection.",
        "sentiment_score": 6,
        "sentiment_description": "Slightly satisfied - The customer seems slightly confused at the beginning and during the conversation, but overall the tone is positive. ",
        "action_items": [
          {
            "owner": "Customer",
            "status": "Not Done",
            "action_item": "Bring the car grant to the inspection appointment."
          }
        ]
      }
      </Output>
      </EXAMPLES>
    """)],
      generation_config=generation_config,
      safety_settings=safety_settings
    )
    
    raw_transcript = responses.text
    if raw_transcript:
        clean_transcript = raw_transcript.replace("```json", "").replace("```", "").strip()
        transcript_json = json.loads(clean_transcript)
        # Query the Firestore collection for the case id
        db = firestore.Client()
        collection_ref = db.collection("audio-files-metadata")
        query = collection_ref.where("gcsUri", "==", audioUri)
        results = list(query.stream())
        db.collection("audio-files-metadata").document(results[0].id).update({"status": "transcript_generated", "raw_transcript": json.dumps(transcript_json, separators=(',', ':'))})

        #Extract sentiment_score from raw_transcript
        sentiment_score = transcript_json["sentiment_score"]

        #Check if sentiment score is below 10
        threshold_score = 10
        if sentiment_score < threshold_score:
                print("Sentiment score is below {threshold_score}. Sending alert to customer.")
                # Send slack alert to customer
                send_alert(caseid, transcript_json, project_id)
        else:
                print("Sentiment score is above {threshold_score}. No need to send alert to customer.")

        # Upload raw transcript to Cloud Storage
        storage_client = storage.Client()
        transcript_bucket_name = project_id + "-operation-insights-transcript"  
        transcript_blob_name = f"raw_transcript_{caseid}.txt"
        transcript_blob = storage_client.bucket(transcript_bucket_name).blob(transcript_blob_name)
        transcript_blob.upload_from_string(raw_transcript, content_type="text/plain")
        
        print(f"Raw transcript uploaded to {transcript_blob_name} in bucket {transcript_bucket_name}")
        
        # Added for logging the transcripts to BigQuery 
        json_transcript = loads(clean_transcript)
        transcript = json_transcript['raw_transcript']
        ai_summary = json_transcript['detailed_summary']
        sentiment_score = json_transcript['sentiment_score']
        sentiment_desc = json_transcript['sentiment_description']
        action_items = json_transcript['action_items']
        dataset_id = "cc_genai_insights"   
        table_id = "genai_transcripts_v1"
        # create_table_if_not_exists(project_id, dataset_id,table_id,)
        writetobq(project_id, dataset_id,table_id,
          caseid, audioUri,modelname,transcript,ai_summary,
          sentiment_score,sentiment_desc,action_items)
          
def writetobq(project_id, dataset_id,table_id,caseid, 
              audioUri,modelname, transcript, ai_summary,
              sentiment_score,sentiment_desc ,action_items):
    """
    Inserts rows into a BigQuery table.

    Args:
        project_id (str): Your Google Cloud project ID.
        dataset_id (str): The BigQuery dataset ID.
        table_id (str): The BigQuery table name.
        rows_to_insert (list): A list of dictionaries, each representing a row to insert.
                               The keys should match the column names in the table.
    """
    log_client = logging.Client()
    logger = log_client.logger("cc_insights_log")
    current_time = dumps(datetime.now(),default=str)
    rows_to_insert = [
            {"case_id": caseid, 
            "timestamp": current_time,
            "model_used":modelname, 
            "language":"EN",
            "audio_uri":audioUri,
            "transcript_uri":"",
            "transcripts":dumps(transcript),
             "transcript_ai_summary":ai_summary,
            "sentiment_score":sentiment_score,
            "sentiment_description":sentiment_desc,
            "action_items":dumps(action_items)
            } 
        ]

    client = bigquery.Client(project=project_id)

    table_ref = client.dataset(dataset_id).table(table_id)

    errors = client.insert_rows_json(table_ref, rows_to_insert)

    if errors == []:
        logger.log_text("New rows have been added.",severity="INFO")
    else:
        logger.log_text("Encountered errors while inserting rows: {}".format(errors),severity="ERROR")

def create_table_if_not_exists(project_id,dataset_id,table_id):
    """
    Checks if a BigQuery table exists. If not, creates it with the provided schema.

    Args:
        project_id (str): Your Google Cloud project ID.
        dataset_id (str): The BigQuery dataset ID.
        table_id (str): The desired table name.
        schema (list): A list of `bigquery.SchemaField` objects defining the table's columns.
    """
    log_client = logging.Client()
    logger = log_client.logger("cc_insights_log")
    schema = [
        bigquery.SchemaField("case_id", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("timestamp", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("model_used", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("language", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("audio_uri", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("transcript_uri", "STRING", mode="NULLABLE"),
        bigquery.SchemaField("transcripts", "STRING", mode="NULLABLE"),
        #bigquery.SchemaField("transcripts", "RECORD", mode="REPEATED",
        #                     fields=[bigquery.SchemaField("transcript", "JSON", mode="NULLABLE")]),
        bigquery.SchemaField("transcript_ai_summary", "STRING", mode="NULLABLE"),
        bigquery.SchemaField("sentiment_score", "INTEGER", mode="NULLABLE"),
        bigquery.SchemaField("sentiment_description", "STRING", mode="NULLABLE"),
        bigquery.SchemaField("action_items", "STRING", mode="NULLABLE"),
        #bigquery.SchemaField("action_items", "RECORD", mode="REPEATED",
        #                     fields=[bigquery.SchemaField("action_item", "JSON", mode="NULLABLE")])
    ]
    client = bigquery.Client(project=project_id)

    # Construct the full table reference
    table_ref = client.dataset(dataset_id).table(table_id)

    try:
        client.get_table(table_ref)
        logger.log_text(f"Table {table_id} already exists in dataset {dataset_id}.",severity="INFO")
    except NotFound:
        # If the table doesn't exist, create it
        table = bigquery.Table(table_ref, schema=schema)
        table = client.create_table(table)  
        logger.log_text(f"Created table {table.project}.{table.dataset_id}.{table.table_id}",severity="INFO")

def send_alert(caseid, transcript_json, project_id):
    """Sends a Slack notification if the sentiment score is below margin."""

    # Construct the Slack message
    print("Creating alert message")
    message = f"🚨 Customer Sentiment Alert 🚨\n\n"
    message += f"Case ID: {caseid}\n"
    message += f"Sentiment Score: {transcript_json['sentiment_score']}\n"
    message += f"Sentiment Description: {transcript_json['sentiment_description']}\n"
    print(message.encode('utf-8'))

    # Publish the message to the Pub/Sub topic
    print("Publishing to topic")
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, TOPIC_ID)
    publisher.publish(topic_path, data=message.encode('utf-8'))
    print("Slack notification message published to Pub/Sub topic.")
    return