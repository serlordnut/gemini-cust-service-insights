import functions_framework
from google.cloud import pubsub_v1
import os
import textwrap
import datetime
import base64
import json
import re
import urllib.request
import requests

SLACK_WEBHOOK_URL = "slack_webhook_url"
SLACK_CHANNEL = "#general"
OAUTH_TOKEN = "oauth_token"

@functions_framework.cloud_event
def trigger_alert_notifications(event):
    """Cloud Function that subscribes to the cc_genai_insights_topic and sends Slack notifications."""

    print("Listening to topic")
    # Get the Pub/Sub message
    # Parse the textPayload as JSON
    payload_json = base64.b64decode(event.data['message']['data']).decode('utf-8')

    # Parse the string into a dictionary
    message_json = {}
    for line in payload_json.splitlines():
        parts = line.split(":", 1)
        if len(parts) == 2:  # Check if there's a colon
            key, value = parts
            message_json[key.strip()] = value.strip()

    # Extract relevant information from the message
    caseid = message_json.get("Case ID")
    sentiment_score = message_json.get("Sentiment Score")
    sentiment_description = message_json.get("Sentiment Description")

    # Construct the Slack message
    message = f"🚨 Customer Sentiment Alert 🚨\n\n"
    message += f"Case ID: {caseid}\n"
    message += f"Sentiment Score: {sentiment_score}\n"
    message += f"Sentiment Description: {sentiment_description}\n"

    # Send the Slack notification by adding OAuth token (xoxb-7259876765811-7312077504853-2UMnZXkiTBZhaRKLvz5EsBXd)
    payload = {
        "token": OAUTH_TOKEN,
        "channel": SLACK_CHANNEL,
        "text": message,
    }
    response = requests.post(SLACK_WEBHOOK_URL, json=payload)

    # Check if the notification was sent successfully
    if response.status_code == 200:
        print("Slack notification sent successfully.")
    else:
        print(f"Error sending Slack notification: {response.text}")