/*
 Copyright 2024 IBM Corp.
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 http://www.apache.org/licenses/LICENSE-2.0
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/

const express = require("express");
const session = require("express-session");
const helmet = require("helmet");
const app = express();

require('dotenv').config();
console.log('Starting application...');
console.log(`APPLICATION_NAME:${process.env.APPLICATION_NAME}`);
console.log(`APPLICATION_PORT:${process.env.APPLICATION_PORT}`);
console.log(`INSTALLATION_TYPE:${process.env.INSTALLATION_TYPE}`);
console.log(`APPLICATION_HOME_LOCAL:${process.env.APPLICATION_HOME_LOCAL}`);
console.log(`APPLICATION_HOME_DOCKER:${process.env.APPLICATION_HOME_DOCKER}`);
console.log(`WA_REGION:${process.env.WA_REGION}`);
console.log(`WA_SERVICE_INSTANCE_ID:${process.env.WA_SERVICE_INSTANCE_ID}`);
console.log(`WA_INTEGRATION_ID:${process.env.WA_INTEGRATION_ID}`);

app.use(helmet({
   contentSecurityPolicy: {
      useDefaults: true,
      directives: {
        "script-src": ["'self'", "web-chat.global.assistant.watson.appdomain.cloud"],
        "default-src": ["'self'", `integrations.${process.env.WA_REGION}.assistant.watson.appdomain.cloud`]
      },
      reportOnly: true
   }
}));

app.use(session({ 
   secret: '32732dwjdw238fgs823ow', saveUninitialized: true, resave: true,
   cookie: {
    secure: true,
    httpOnly: true,
    sameSite: 'strict'
  }
}));

app.use(express.json());
app.use(express.static("public"));

app.get("/assistant-integration.json", (req, resp, next) => {
   resp.send({
         integrationID: process.env.WA_INTEGRATION_ID,
         region: process.env.WA_REGION,
         serviceInstanceID: process.env.WA_SERVICE_INSTANCE_ID
   });
   next();
});

var http = require('http');

http.createServer(app).listen(process.env.APPLICATION_PORT,function () {
   console.log(`${process.env.APPLICATION_NAME} is listening on port ${process.env.APPLICATION_PORT}`);

});


