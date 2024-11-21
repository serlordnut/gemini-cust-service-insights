import base64
import json
import os
import google.cloud.dlp
from google.cloud import storage
import urllib.request

# get project_id
url = "http://metadata.google.internal/computeMetadata/v1/project/project-id"
req = urllib.request.Request(url)
req.add_header("Metadata-Flavor", "Google")
project_id = urllib.request.urlopen(req).read().decode()
print(project_id)

DESTINATION_BUCKET_NAME = project_id + "-operation-insights-deidentified"

def deidentify_and_upload(event, context):
    """
    Triggered by a file upload to Cloud Storage.
    De-identifies the content of the file using DLP API and uploads it to another bucket.
    """

    print ("In the bucket function")
    print (event)
    # Get the file name and bucket from the event
    file_name = event['name']
    SOURCE_BUCKET_NAME = event['bucket']

    # Get the file from the source bucket
    storage_client = storage.Client()
    bucket = storage_client.bucket(SOURCE_BUCKET_NAME)
    blob = bucket.blob(file_name)
    file_content = blob.download_as_text()

    # De-identify the file content using DLP API
    dlp = google.cloud.dlp_v2.DlpServiceClient()

    # Convert the project id into a full resource id.
    parent = f"projects/" +project_id + "/locations/asia-southeast1"
    
    #  Add infoTypes to your DLP request  
    info_types = [
        {"name": "PHONE_NUMBER"},
        {"name": "PERSON_NAME"},
        {"name": "EMAIL_ADDRESS"},
        {"name": "CREDIT_CARD_NUMBER"},
    ]

    inspect_config = {
        "info_types": info_types,
    }

    # Construct deidentify configuration dictionary
    deidentify_config = {
        "info_type_transformations": {
            "transformations": [
                {"primitive_transformation": {"replace_with_info_type_config": {}}}
            ]
        }
    }

    # Call the API
    response = dlp.deidentify_content(
        request=google.cloud.dlp_v2.DeidentifyContentRequest({
            "parent": parent,
            "deidentify_config": deidentify_config,
            "inspect_config": inspect_config,
            "item": {"value": file_content},
        })
    )
    
    print (response.item.value)

    # Upload de-identified content
    destination_blob = storage_client.bucket(DESTINATION_BUCKET_NAME).blob(file_name)
    destination_blob.upload_from_string(response.item.value)

    print(f"De-identified file '{file_name}' uploaded to '{DESTINATION_BUCKET_NAME}'")