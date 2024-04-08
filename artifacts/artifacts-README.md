
# ARTIFACT CONFIGURATION STEPS

## Automated Steps

### Automated configuration artifacts for watsonx Assistant

1.	Create Assistant (Assistant workspace/project) - 
- https://cloud.ibm.com/apidocs/assistant-v2#createassistant

Input:
- watsonx service instance id (from the DA, e.g., 88888888-x888-88xx-xx88-x8x888888888)
- Assistant name: gen-ai-rag-sample-v1
- Location (from the DA, e.g.,- us-south)

Output:
- From the response JSON get the 
- "assistant_id"
- "environment"."draft"."environment_id"


2. Get Assistant environment integration id etc. for web chat interface
- https://cloud.ibm.com/apidocs/assistant-v2#getenvironment

Input: 
- service instance id (from the DA)
- assistant id (from previous API call)
- environment id (from previous API call)

Output:
- From the response JSON get the "environment"."draft".integration_id":"23769f91-26ff-4bee-82f3-096bc5d31c04"


3. Set the watsonx service id/instance id, region and integration id in the deployment environment variables

WA_REGION=us-south

WA_SERVICE_INSTANCE_ID=88888888-x888-88xx-xx88-x8x888888888

WA_INTEGRATION_ID=x8xxxxx-8xx8-88x8-888x-xx88xxx88x88


### Automated configuration artifacts for Watson Discovery

1.	Create Discovery Project
- https://cloud.ibm.com/apidocs/discovery-data#createproject

2.	Create Colleciton in the Project
- https://cloud.ibm.com/apidocs/discovery-data#createcollection

3.	Import trainig model to the Collection
File: WatsonDiscoveryModel.sdumodel
- Details TBD. Currently manual step. Does not appear to have API.

4.	Add/Upload PDF files to the collections
- https://cloud.ibm.com/apidocs/discovery-data#adddocument
- Documents: FAQ-1.pdf...FAQ-7.pdf (7 documents)

5.	Get the URL/Instance ID, Project and Collection ID
- Captured from the steps done before


### Automated configuration artifacts for watsonx.ai

1.	Create user profile in watsonx
- Create profile for the "application owner" user that was created before by the Users and Secrets DA 
- https://github.ibm.com/dap/dap-planning/issues/32444#issuecomment-73563335

2.	Create watsonx Project with artifacts
- Associate Object Storage and Machine Learning
- Add the RAG enabler pattern assets - Project Template, data sets etc. to the watsonx Project.
- https://github.ibm.com/dap/dap-planning/issues/32968

3.	Deploy the Project Template to Deployment Space
- Get the private and public endpoints for inferencing deployment
- https://github.ibm.com/dap/dap-planning/issues/32969

## Manual Steps

### Manual configuration artifacts for watsonx Assistant


1. Login to watsonx Assistant 
2. Select "gen-ai-rag-sample-v1" Assistant
3. Create custom extension for Watson Discovery by importing the OpenAI json file

Navigate left bottom menu to Integrations>Extensions>"Build custom extension"

Enter the the following-

Extension name : watson-discovery-custom-ext-v1

Upload a OpenAPI json file: watson-discovery-custom-ext-api-openapi.json

Save the custom extension

Open the watson-discovery-custom-ext-v1 custom extension tile

Add/Open and configure the authentication (username/API key) and URL etc. used by the extension during runtime. 

Username: apikey

API Key: get from the Watson Discovery instance UI

Watson Discovery URL: get from the Watson Discovery instance UI

Save the configuration.


4. Create custom extension for watsonx Assistant by importing the OpenAI json file

Navigate left bottom menu to Integrations>Extensions>"Build custom extension"

Enter the the following-

Extension name : watsonx-ai-custom-ext-v1

Upload a OpenAPI json file for your location: 

US-us-south: watsonx-ai-custom-ext-us-south-api-openapi.json 

EU-fr-de: watsonx-ai-custom-ext-fr-de-api-openapi.json (TBD)

JP-jp-tok: watsonx-ai-custom-ext-jp-tok-api-openapi.json (TBD)

Save the custom extension

Open the watsonx-ai-custom-ext-v1 custom extension tile

Add/Open and configure the authentication API key used by the extension during runtime. 

API Key: get from the user

Save the configuration.

5. Create the RAG pattern Action skill by importing the Assistant zip file

Navigate left bottom menu to Assistant setting>Download/Upload>Download/Upload files>Assistant only

Upload assistant as a ZIP file: watsonx-assistant-gen-ai-sample-v1.zip

Alternatively:

Navigate top right menu>Global settings>Upload/Download

Upload Action skill as action json file: watsonx-assistant-gen-ai-sample-v1.json

6. Confirm uploads and imports are successful

Actions> All items>Created by you

Actions> Variables>Created by you

7. Edit/change the variables values

Actions> Variables>Created by you

Watson Discovery Project ID

watsonx.ai Project ID



### Manual configuration artifacts for Watson Discovery
1. Login to  Watson Discovery
2. Select Project 
3. Select Collection
4. Import SDU trainig model to the Collection
File: WatsonDiscoveryModel.sdumodel

### Manual configuration artifacts for watsonx.ai
None

