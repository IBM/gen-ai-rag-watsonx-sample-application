## Removing the watsonx Assistant artifacts

Undeploying the "4 - WatsonX SaaS services" from the RAG Deployable Architecture Stack will remove the watsonx Assistant and all the artifacts that were added manually. It will also remove other watsonx instances. To remove watsonx Assistant artifacts individually, launch watsonx Assistant UI, select gen-ai-rag-sample-v1 Assistant workspace and follow the cleanup options below.

__Removing Custom Extensions only__

To remove the Custom extensions, navigate left bottom menu to Integrations>Extensions. 
Find the custom extension to remove (watson-discovery-custom-ext-v1 and watsonx-ai-custom-ext-v1) and click on the three dots and "Remove from catalog" to remove the custom extension. Note that this will break the Actions that are using the Custom extension.

__Removing Actions and Variables only__

To remove the Actions and Variables created from the Actions import JSON, navigate Home>Actions> All items>Created by you and Navigate Home>Actions> Variables>Created by you and delete each entry manually. The Assistant's workspace IDs will remain same and sample application will continue to use this Assistant. You can create your own Actions and Variables or reimport the Actions JSON file if needed.

__Removing Assistant workspace__

To fully remove the Assistant workspace, Navigate left bottom menu to Assistant settings>Delete assistant. Note that you will need to "Deploy again" the Deployable Architectures - Sample RAG app configuration Stack and Toolchain". This will create a new Assistant and redeploy the sample application with IDs of the new Assistant.

