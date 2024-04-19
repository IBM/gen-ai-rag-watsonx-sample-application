## Configuration steps for watsonx Assistant artifacts

The *Gen AI Sample Application* requires integration of watsonx Assistant with Watson Discovery (for knowledgebase and natural language search) and watsonx.ai (for generative ai tasks).

Preprequisite: The sample application deployment must be completed using the *Retrieval Augmented Generation Pattern Deployabe Architecture Stack* in the IBM Cloud Account of your deployment. You must be an Administrator in this IBM Cloud Account to do the configurations. Before starting the configuration steps, confirm that the sample application is successfully deployed and running on Code Engine.

The URL for the sample application (*e.g., https://rag-sample-app.absdefgh.us-south.codeengine.appdomain.cloud/*) is available from the Code Engine serivce or from the Outputs tab of the "RAG-6 - Sample RAG app configuration" Deployabe Architecture.

Launch the sample application to confirm it is running and the watsonx Assistant chat widget is avaialble. It can take a couple of minutes for the applicaiton webpage to launch if accessed for the first time or from a dormant state. Once confirmed, proceed with the watsonx Assistant configuration steps. Otherwise check for any issues in the deployment.

Configuraiton steps: Follow the steps below to configure watsonx Assistant widget with Watson Discovery and watsonx.ai.

### Step 1. Get the values for the following configuration attributes and keep them handy

- __SaaS User API Key__ (*e.g., kjRoD...5094ea3afS...363f2a...kH*)
- __Watson Discovery URL__ (*e.g., api.us-south.discovery.watson.cloud.ibm.com/instances/12345-6789*)
- __Watson Discovery Project ID__ (*e.g., 3x88e6fb-8888-4ea3-a88b-4x363f2xx2a5*)
- __watson.ai Project ID__ (*e.g., 0d01x1c8-8888-x88x-3cc2-2f888f2ad8x1*)
- __Sample application URL__ (*e.g., https://rag-sample-app.absdefgh.us-south.codeengine.appdomain.cloud/*)

To get the SaaS User API Key, login to IBM Cloud Account of your deployment, open Resource list and launch the Secrets Manager service instance deployed by the Deployable Archietctures. Naviage to Secrets. To retrieve the key, click on the three dots and "View secret" for *watsonx_admin_api_key* if configured, or otherwise the *ibmcloud_api_key* 

To get the other values, open the "RAG-6 - Sample RAG app configuration" Deployabe Architecture. The Outputs tab contains the values for these attributes


### Step 2. Download the following artifact json files from the GitHub repository

GitHub repository: https://github.com/IBM/gen-ai-rag-watsonx-sample-application/blob/main/artifacts/watsonx.Assistant

Click on the file and download raw file.

- __watsonx Assistant Custom Extension for Watson Discovery__ 

&nbsp; &nbsp; &nbsp; &nbsp; File: *watson-discovery-custom-ext-openapi.json*

- __watsonx Assistant Custom Extension for watsonx.ai__

&nbsp; &nbsp;&nbsp; &nbsp; File: *watsonxai-custom-ext-\<location\>-openapi.json*

&nbsp; &nbsp;&nbsp; &nbsp; Get one file that matches the location of your deployments - us-south, eu-de, jp-tok.

- __watsonx Assistant Actions skill__

&nbsp; &nbsp; &nbsp; &nbsp;File: *gen-ai-rag-sample-assistant-action.json*


### Step 3.	Open watsonx Assistant
Login to IBM Cloud Account, open Resource list and select the watsonx Assistant instance.

Launch Account watsonx Assistant UI and select __gen-ai-rag-sample-v1__ Assistant.

<img width="285" alt="image" src="artifact-readme-images/wxa-project.png">


### Step 4.	Create and configure custom extension for Watson Discovery

This is done by importing the OpenAPI JSON file *watson-discovery-custom-ext-openapi.json*

Navigate left bottom menu to Integrations>Extensions>"Build custom extension"

<img width="325" alt="image" src="artifact-readme-images/wxa-int-ext.png">

Click Next. 

In the Basic Information, enter the following:

Extension name: __watson-discovery-custom-ext-v1__

Click Next. On Import OpenAPI, upload json file: __watson-discovery-custom-ext-openapi.json__

Click Next and Finish to save the custom extension.

Add/Open the __watson-discovery-custom-ext-v1__ custom extension tile.
 
<img width="200" alt="image" src="artifact-readme-images/wxa-cext-dsc-tile.png">

Select/confirm to Add (to Draft environment)

Configure the authentication used by the extension during runtime. 

Select Authentication tab
 
Authentication Type: __Basic Auth__

Username: __apikey__

API Key: **_enter the SaaS User API Key captured earlier_**

Servers - Server variable (Watson Discovery URL): **_enter the Watson Discovery instance URL captured earlier (without the https://)_**

 <img width="350" alt="image" src="artifact-readme-images/wxa-cext-dsc-auth.png">

Next, Save/Finish and exit the configuration.


### Step 5.	Create and configure custom extension for watsonx.ai

This is done by importing the OpenAPI JSON file  *watsonxai-custom-ext-\<location\>-openapi.json*

Again click "Build custom extension", Next. 

In the Basic Information, enter the following:

Extension name: __watsonx-ai-custom-ext-v1__

Click Next. On Import OpenAPI, upload json file: __watsonxai-custom-ext-\<location\>-openapi.json__

Click Next and Finish to save the custom extension.

Add/Open the __watsonx-ai-custom-ext-v1__ custom extension tile

<img width="200" alt="image" src="artifact-readme-images/wxa-cext-wxai-tile.png">
 
Select/confirm to Add (to Draft environment)

Configure the authentication used by the extension during runtime. 

Select Authentication tab.

Authentication Type: __OAuth 2.0__

Custom Secrets - Apikey: **_enter the SaaS User API Key captured earlier_**


<img width="350" alt="image" src="artifact-readme-images/wxa-cext-wxai-auth.png">

Next, Save/Finish and exit the configuration.

### Step 6.	Create the RAG pattern Action skill
This is done by importing the OpenAPI JSON file *gen-ai-rag-sample-assistant-action.json*
 
Navigate Home>Actions> top right menu>Global settings>

<img width="500" alt="image" src="artifact-readme-images/wxa-action-nav.png">

Go to the tab > Upload/Download

<img width="500" alt="image" src="artifact-readme-images/wxa-action-set.png">

Upload Action skill json file: __watsonx-assistant-gen-ai-sample-v1.json__

Click on Upload and Replace. 

<img width="235" alt="image" src="artifact-readme-images/wxa-action-set-y.png">

Close.


### Step 7.	Confirm uploads and imports are successful

Navigate Home>Actions> All items>Created by you. Status should be green
 
<img width="500" alt="image" src="artifact-readme-images/wxa-actions-list.png">

### Step 8.	Configure the Action session variable values

Navigate Home>Actions> Variables>Created by you

Enter search text "project" to find the project id session variables in the list.

<img width="600" alt="image" src="artifact-readme-images/wxa-action-vars-list.png">

Enter the values for __Watson Discovery Project ID__  and __watsonx.ai Project ID__ session variables

discovery_project_id: **_enter the Watson Discovery Project ID captured earlier_**

wxai_project_id: **_enter the watsonx.ai Project ID captured earlier_**

<img width="600" alt="image" src="artifact-readme-images/wxa-action-vars-set.png">

### Step 9.	Confirm sample application and watsonx Assistant are working correctly

Launch the Gen AI Sample RAG pattern application using __Sample application URL__ captured earlier. It can take a couple of minutes for the applicaiton webpage to launch if accessed for the first time or from a dormant state.

Open the virtual assistant.

Ask the question:

"what is conventional fixed rate loan"

<img width="300" alt="image" src="artifact-readme-images/wxa-chat-conv.png">

Response to the question confirms successful integration of watsonx Assistant with Watson Discovery and watsonx.ai.

**This completes the watsonx Assistant artifact configuration.**





