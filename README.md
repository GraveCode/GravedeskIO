## Synopsis

Gravedesk is a web and email based helpdesk ticket tracker. This project - GravedeskIO - is the node.js based backend server that handles email processing and the database, as well as provides data to the website frontend - GravedeskWeb - via socket.io. 

We needed a simple to use ticket system for our IT Support department, that would work well with the many help requests received to our support email address. 

## Features

- node.js based server
- uses socket.io to communicate with the frontend website
- individual tickets have a friendly text-message style view
- uses google OAUTH2 authentication for federated account management, including support for restricting to a single google apps domain
- uses context.io for timely retrieval of email messages

## Requirements

- a sysadmin comfortable with hosting a full-web app - hopefully you!
- server to host this node.js application (tested on ubuntu server)
- webserver to host static website created by GravedeskWeb (tested on nginx)
- CouchDB database
- Redis database
- email account with internet visible IMAP; or google email account
- free Context.IO account for email processing
- google API oauth2 ID, for authenticating login accounts via google
- (optional) google apps domain

## Installation

### Pre-requisites

- Install node.js on host server
- Install and obtain login credentials for couchdb and redis. Can be installed on the same host as node.js, or provided by 3rd party
- Sign up for free account at context.io
- sign up for free account at google console

### Add monitored email account at context.io

- This email account will be monitored for new emails to turn into tickets, so should be uniquely used for this purpose
- e.g. `itsupport@example.com` with IMAP support
- once logged into context.io, add account
- supply login and IMAP credentials (if needed)
- note the id of that particular email account under account properties
- now, goto `settings/API keys and libraries`
- create an OAuth client ID and secret

### Create google API oauth2 credentials

- create new project at https://cloud.google.com/console/project
- Under APIs & auth \ Credentials, create a new client ID of type `Web Application`
- add authorized redirect URL of the form `http://itsupport.example.com/node/google/return` using your own domain where the site will be accessible to clients
- (optional) add `https://itsupport.example.com/node/google/return` as an extra redirect URI for SSL hosted websites
- create client ID, and make a note of the generated ID and secret

### setup GravedeskIO

- copy GravedeskIO source to host server running node.js
- e.g. `git clone https://github.com/GraveCode/GravedeskIO.git`
- change to GravedeskIO directory
- run `npm install -d` to install necessary libraries
- copy `settings-example.coffee` to `settings.coffee`
- edit `settings.coffee` to the appropriate settings
- - add couchdb & redis server settings
- - add port the server will run on
- - add the URL that the client-facing webserver GravedeskWeb will be on
- - add the google OAUTH2 client ID and secret created earlier
- - add the  context.io OAUTH key and secret created earlier, as well as the email address and account id of the email address used for tickets
- - add the email accounts of helpdesk admins who will be allowed to manage the tickets
- - (optional) add or modify the list of groups tickets can be moved into if desired; the first will be the default location for new tickets from users
- run the server with `node app.js`
- (optional) alternatively, `npm install -g forever` to keep the server running in the background, and start with `forever start app.js`
- go and setup a GravedeskWeb website to access and manage the service!

## License

A short snippet describing the license (MIT, Apache, etc.)