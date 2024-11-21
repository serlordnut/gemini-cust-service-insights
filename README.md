
# Gemini Customer Service Insights


## Getting started

  

Welcome to the Showcase of Gemini Powered Customer Insights Platform

  
  

## Name

Gemini Customer Service Insights Platform

  

## Description

Enterprises are looking to modernize how they gain insights from customer service interactions, including audio calls and chat transcripts. Currently, their reliance on manual processes for reporting, quality checks, and action item tracking is time-consuming and limits their ability to analyze a comprehensive view of customer interactions.

  

Generative AI solutions, such as Gemini, offer a transformative approach. By automating these processes, enterprises can significantly enhance productivity, improve customer satisfaction, and gain invaluable insights into their operations.

  
  

## Installation

  

1. Remove existing terraform state files & rerun terraform insights


`cd terraform/ && rm -rf terraform.tfstate* && rm -rf .terraform* && terraform init`


&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Note: Install terraform if needed: https://developer.hashicorp.com/terraform/install


2. Update variables.tfvars parameters with project_id

3. Apply terraform
  
`terraform apply -var-file="variables.tfvars"`

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;3.a (NOTE) If Project name is too long - Sometimes bucket creation fails. Reduce the project name length to fix issue.  


4. Configure consent screen https://console.cloud.google.com/apis/credentials/consent

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;4.a Choose External

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;4.b Update application home page with URL from Cloud Run App

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;4.c Update Authorized domain with domain from Cloud Run App URL

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;4.d Leave Scope default - Save & Continue

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;4.e If any errors seen in Login Oauth -  You might need to add email address here.
  

5. Generate oAuth Client Credentials in API Credentials Page. https://console.cloud.google.com/apis/credentials. In Callback URL setting using URL of Cloud Run deployed followed by /auth/google/callback

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;5.a Click Create credentials

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;5.b Choose oAuth Client Id

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;5.c Application type - Web Application

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;5.d Update Name "Customer Service Insights"

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;5.e Update javascript origins - with URL from Cloud Run App

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;5.f Update Redirect URL - with URL from Cloud Run App followed by /auth/google/callback

For example

`https://CLOUD_RUN_DEPLOYED_URL/auth/google/callback`


6. Update Config.js in dashboard-app folder with Client Id, Client Secret, Callback URL, from API Credentials & update customer domain and "google.com" domain in allowed domains, update Project Id

  
7. Upload logo and banner of customer into public/logos/

8. Update html_files/login.html, views/upload.ejs with logo and banner links , update styles.css line 1 with primary color of customer branding.

9. <b>Navigate to /dashboard-app folder</b>, Deploy the application again with changes, make sure you replace customer_name below.

`cd ../dashboard-app`

`gcloud run deploy ccinsights --region=asia-southeast1 --source .`

10. Access the Cloud Run App via URL to see the app in action.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;10.a Make sure you login with email domain that is allow-listed (google.com) in "config.js"

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;10.b If you see any errors in cloud function saying IPV4 permission denied error, Navigate to vertex AI Stuido, Choose Flash & Region "Singapore", Upload sample audio in the UI. There is a bug where Vertex AI API warms up only when manually triggered in the UI.


<br><br>



11. Execute below git commands to untrack config changes

`git update-index --assume-unchanged dashboard-app/config.js`

`git update-index --assume-unchanged terraform/variables.tfvars`

`git update-index --assume-unchanged dashboard-app/public/logos/*`

`git update-index --assume-unchanged terraform/terraform.tfstate`

12. Install ApigeeX eval with External Access Routing: https://cloud.google.com/apigee/docs/api-platform/get-started/overview-eval

Take a note of the domain <LoadBalancerIP>.nip.io, this will be needed to update swagger spec in apigee/api-specs/audio-files.yaml at line 7

13. Enable Application Integration: https://cloud.google.com/application-integration/docs/setup-application-integration

14. Install the Application Integration CLI with the following command:

`curl -L https://raw.githubusercontent.com/GoogleCloudPlatform/application-integration-management-toolkit/main/downloadLatest.sh | sh -`

15. Set integrationcli preferences:

`token=$(gcloud auth print-access-token)`

`project=<PROJECT_ID>`

`region=<APP_INT_REGION>`

`integrationcli prefs set -p $project -r $region -t $token`

16. Update the values at:

`application-integration/firestore-integration/dev/config-variables/FirestoreIntegration-config.json`

17. Create an auth profile at https://console.cloud.google.com/integrations/auth-profiles

Authentication profile name: Firestore Auth Profile

Authentication type: Service Account

Service Account: gcf-sa@<PROJECT_ID>.iam.gserviceaccount.com

Scopes: https://www.googleapis.com/auth/datastore

18. Change to the application-integration/firestore-integration folder and deploy the Firestore Integratiion:

`cd application-integration/firestore-integration/` 

`integrationcli integrations apply -f . -e dev --wait=true`

19. Change to the apigee/audio-files-v1 folder and Deploy the Apigee Artifacts by replacing the <PROJECT_ID> with the correct value:

`cd apigee/audio-files-v1`

`mvn clean install -P eval -Dbearer=$(gcloud auth print-access-token) -Dorg=<PROJECT_ID> -DgoogleTokenEmail=gcf-sa@<PROJECT_ID>.iam.gserviceaccount.com  -Dapigee.config.options=create`

20. Create a developer portal 

Open https://apigee.google.com/

Under Publish on the left side go to Portals

Click on +Portal to create a new one

Give it a name and description

Under Themes update the Primary color and logo

Click on Save and the Click on Publish

Under API Catalog, click on + in API's tab

Select the Audio-Files-ReadOnly product

Add the updated OpenAPI spec (apigee/api-specs/audio-files.yaml)

Check the Published (listed in the catalog) box and Save

Open the developer portal (Link on the Portals page)

Click on Sign In

Click on Create an account

Enter your details and Create an account, verfiy via email and login

Once logged in go to your email and Click on Apps

Create a new App

Give it any name and Enable the Audio-Files-ReadOnly product

Save (this will generate the credentials for accessing the API)

Go to API's on the Top of the Screen

Authorize with the recently created App

Test the paths with data created as part of your testing

