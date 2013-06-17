## modules & variables

settings = require './settings'
express = require 'express'
async = require 'async'
app = express()
nano = require('nano')(settings.dbServer)
db = nano.use settings.dbName


## routes

app.get '/', (req, res) ->
	res.send ('Hello World')

## start servers

async.series([
	(callback) ->
		# couchdb connection
		nano.db.create settings.dbName, (err, body) ->		
			if err
				# db probably already exists, let's check
				nano.db.get settings.dbName, (err, body) ->
					# couldn't get db info, we have a problem
					if err
						console.log 'Error connecting to ' + settings.dbName + ' on ' + settings.dbServer
						callback (err)
					else
						console.log 'Connected to database ' + settings.dbName + ' on ' + settings.dbServer
						callback (null)
			else
				# db successfully created - first run!
				console.log 'Database ' + settings.dbName + ' on ' + settings.dbServer + ' created!'
				callback(null)

	, (callback) -> 
		# express
		app.listen settings.defaultport
		console.log 'Listening on port ' + settings.defaultport
		callback null

], (err) ->
# callback error handler
	if err
		console.log "Problem with starting core services; "
		console.log err
		process.exit err
)