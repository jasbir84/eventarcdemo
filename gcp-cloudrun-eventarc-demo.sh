#!/bin/bash


export REGION="us-central1"
export PROJECT_ID="XXXXXXXXXXX"
export SERVICE_NAME="event-display"

gcloud projects create $PROJECT_ID

gcloud config set project $PROJECT_ID
gcloud config set run/region $REGION
gcloud config set run/platform managed
gcloud config set eventarc/location $REGION

export PROJECT_NUMBER="$(gcloud projects list --filter=$(gcloud config get-value project) --format='value(PROJECT_NUMBER)')"

# Enable billing
gcloud services enable cloudbilling.googleapis.com
gcloud alpha billing accounts list
export BILLING_ID="xxxxx" # From above
gcloud alpha billing projects link $PROJECT_ID --billing-account $BILLING_ID

# Enable APIs
gcloud services enable run.googleapis.com
gcloud services enable eventarc.googleapis.com
gcloud services enable logging.googleapis.com
gcloud services enable cloudbuild.googleapis.com

gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
  --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com"\
  --role='roles/iam.serviceAccountTokenCreator'

gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
  --member=serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
  --role='roles/eventarc.eventReceiver'

# gcloud beta eventarc attributes types list
# gcloud beta eventarc attributes types describe google.cloud.pubsub.topic.v1.messagePublished

gcloud run deploy $SERVICE_NAME \
  --image gcr.io/knative-releases/knative.dev/eventing-contrib/cmd/event_display@sha256:8da2440b62a5c077d9882ed50397730e84d07037b1c8a3e40ff6b89c37332b27 \
  --allow-unauthenticated

gcloud eventarc triggers create trigger-pubsub \
  --destination-run-service=$SERVICE_NAME \
  --destination-run-region=$REGION \
  --event-filters="type=google.cloud.pubsub.topic.v1.messagePublished"

export TOPIC_ID=$(gcloud eventarc triggers describe trigger-pubsub --format='value(transport.pubsub.topic)')

gcloud eventarc triggers list

gcloud pubsub topics publish $TOPIC_ID --message="Hello there"

gcloud eventarc triggers delete trigger-pubsub

export BUCKET_NAME=cr-bucket-$(gcloud config get-value project)
gsutil mb -p $(gcloud config get-value project) \
  -l $(gcloud config get-value run/region) \
  gs://$BUCKET_NAME/

# In order to receive events from a service, you need to enable Cloud Audit Logs.
# From the Cloud Console, select IAM & Admin and Audit Logs from the upper left-hand menu.
# In the list of services, check Google Cloud Storage:
# On the right hand side, make sure Admin, Read and Write are selected. Click save.

# From the Cloud Console, select Logging and Logs Viewer from the upper left-hand menu.
# Under Query Builder, choose GCS Bucket and choose your bucket and its location. Click Add.
# Note: There is some latency for audit logs to show up in Logs Viewer UI.
# If you don't see GCS Bucket under the list of resources, wait a little before trying again.
# Once you run the query, you'll see logs for the storage bucket and one of those should be storage.objects.create

echo "Hello World" > random.txt
gsutil cp random.txt gs://$BUCKET_NAME/random.txt

gcloud eventarc triggers create trigger-auditlog \
  --destination-run-service=$SERVICE_NAME \
  --destination-run-region=$REGION \
  --event-filters="type=google.cloud.audit.log.v1.written" \
  --event-filters="serviceName=storage.googleapis.com" \
  --event-filters="methodName=storage.objects.create" \
  --service-account=$PROJECT_NUMBER-compute@developer.gserviceaccount.com

gsutil cp random.txt gs://$BUCKET_NAME/random.txt

gcloud eventarc triggers delete trigger-auditlog
