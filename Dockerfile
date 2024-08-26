FROM registry.access.redhat.com/ubi9/nodejs-16@sha256:1c015c86115262f366290f91a2387b64ce0695041db0dd3226b478836088e916

USER root
RUN yum update -y && yum upgrade -y
RUN npm -v

#Set environment variables to be used by the application
#for configuration and integration files
#Other variables must be set in app.properties

ENV APPLICATION_HOME_DOCKER=/usr/src/app
ENV APPLICATION_PORT=8080

# Create app directory
WORKDIR $APPLICATION_HOME_DOCKER

# Install app dependencies
# A wildcard is used to ensure both package.json AND package-lock.json are copied
# where available (npm@5+)
COPY package*.json ./

# Get the node_modules
RUN npm install

# Bundle app source
COPY . .
#Set shell script permissions
RUN chmod 755 $APPLICATION_HOME_DOCKER/utils/*.sh

# set file permissions
RUN chown -R 1001:0 ${APPLICATION_HOME_DOCKER} && chmod -R u+rwx ${APPLICATION_HOME_DOCKER} && \
    chmod -R g=u ${APPLICATION_HOME_DOCKER}

USER 1001

#EXPOSE 8080
EXPOSE $APPLICATION_PORT

CMD ["npm", "start"]
