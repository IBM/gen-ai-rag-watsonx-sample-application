## Removing the watsonx Assistant artifacts

Steps to remove deployments and configurations made by v2.0.0 of the [RAG Pattern deployable architecture](
https://cloud.ibm.com/catalog/7a4d68b4-cf8b-40cd-a3d1-f49aff526eb3/architecture/Retrieval_Augmented_Generation_Pattern-5fdd0045-30fc-4013-a8bc-6db9d5447a52-global):

Undeploying the "Gen AI - WatsonX SaaS services" from the RAG Deployable Architecture Stack will remove the watsonx Assistant and all the artifacts that were added manually. It will also remove other watsonx instances. To remove watsonx Assistant artifacts individually, launch watsonx Assistant UI, select your gen-ai-rag-sample-app-assistant Assistant workspace and follow the cleanup options below.

__Removing Actions and Variables only__

To remove the Actions and Variables created from the Actions import JSON, navigate Home>Actions> All items>Created by you and Navigate Home>Actions> Variables>Created by you and delete each entry manually. The Assistant's workspace IDs will remain same and sample application will continue to use this Assistant. You can create your own Actions and Variables or reimport the Actions JSON file if needed.

__Removing Assistant workspace__

To fully remove the Assistant workspace, Navigate left bottom menu to Assistant settings>Delete assistant. Note that you will need to "Deploy again" the Deployable Architecture - Workload - Sample RAG App Configuration". This will create a new Assistant and redeploy the sample application with IDs of the new Assistant.


---

Steps to remove deployments and configurations made by v1.x of the [RAG Pattern deployable architecture](
https://cloud.ibm.com/catalog/7a4d68b4-cf8b-40cd-a3d1-f49aff526eb3/architecture/Retrieval_Augmented_Generation_Pattern-5fdd0045-30fc-4013-a8bc-6db9d5447a52-global):

Undeploying the "4 - WatsonX SaaS services" from the RAG Deployable Architecture Stack will remove the watsonx Assistant and all the artifacts that were added manually. It will also remove other watsonx instances. To remove watsonx Assistant artifacts individually, launch watsonx Assistant UI, select gen-ai-rag-sample-v1 Assistant workspace and follow the cleanup options below.

__Removing Custom Extensions only__

To remove the Custom extensions, navigate left bottom menu to Integrations>Extensions. 
Find the custom extension to remove (watson-discovery-custom-ext-v1 and watsonx-ai-custom-ext-v1) and click on the three dots and "Remove from catalog" to remove the custom extension. Note that this will break the Actions that are using the Custom extension.

__Removing Actions and Variables only__

To remove the Actions and Variables created from the Actions import JSON, navigate Home>Actions> All items>Created by you and Navigate Home>Actions> Variables>Created by you and delete each entry manually. The Assistant's workspace IDs will remain same and sample application will continue to use this Assistant. You can create your own Actions and Variables or reimport the Actions JSON file if needed.

__Removing Assistant workspace__

To fully remove the Assistant workspace, Navigate left bottom menu to Assistant settings>Delete assistant. Note that you will need to "Deploy again" the Deployable Architectures - Sample RAG app configuration Stack and Toolchain". This will create a new Assistant and redeploy the sample application with IDs of the new Assistant.

