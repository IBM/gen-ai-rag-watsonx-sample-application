fetch("assistant-integration.json")
    .then(resp => {
        if (resp.status === 200) {
            return resp.json()
        } else {
            return Promise.reject("Unable to fetch integration parameters")
        }
    })
    .then(addChatWidget)
    .catch(console.error)

function addChatWidget(watsonAssistant) {
    window.watsonAssistantChatOptions = {
        integrationID: watsonAssistant.integrationID,
        region: watsonAssistant.region,
        serviceInstanceID: watsonAssistant.serviceInstanceID,
        clientVersion: watsonAssistant.clientVersion,
        onLoad: async (instance) => {
            await instance.on({ type: 'view:change', handler: check_wx_configs });
            await instance.render();
        }
    };
    setTimeout(function(){
        const t=document.createElement('script');
        t.src="https://web-chat.global.assistant.watson.appdomain.cloud/versions/" + (watsonAssistant.clientVersion || 'latest') + "/WatsonAssistantChatEntry.js";
        document.head.appendChild(t);
    });
    return true;
}
var checkIterations=0;
var maxCheckIterations=5;
var checkPause=3000;

function check_wx_configs(event) {

        if ( (checkIterations>0) && (checkIterations<maxCheckIterations) ) {

            setTimeout(function() {
                        if  ( (document.getElementsByClassName("WACWidget__MarkdownP")[0] == null &&
                               document.getElementsByClassName("WACHomeScreen__greeting")[0] == null) )  {
                        //not configured.
                        var elemDiv = document.createElement('div');
                        elemDiv.style.cssText='position:fixed; left:0; right:0; top:0; border:1px solid blue; background:#fbe698; margin: 1em; padding: 1em; z-index:1000; font-family:IBM Plex Sans; font-size:16px; color:#003399';
                        elemDiv.innerHTML = '<div style="display:flex; justify-content:space-between"><div align="left"> \
                                &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Congratulations! The sample application webpage is now up and running! \
                                <br>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Please follow the steps described \
                                <a href="https://github.com/IBM/gen-ai-rag-watsonx-sample-application/blob/main/artifacts/artifacts-README.md" target="_blank">here</a> to complete the watsonx Assistant configurations. \
                                <br>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Once completed, reopen this webpage in a new browser window and start using the application.</div></div>'

                        document.body.appendChild(elemDiv);

                        checkIterations=maxCheckIterations+1; //stop future checks
                        }
                }, checkPause);
        }
        checkIterations++;

}; //end of function check_wx_configs()