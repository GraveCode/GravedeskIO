## modules & variables

settings = require './settings'
dbinit = require './lib/dbinit'
express = require 'express'
async = require 'async'
app = express()
db = null

## routes

require('./routes')(app)

## start servers

async.series([
	(callback) ->
		# setup couchdb database connection
		dbinit settings.couchdb, (err, database) ->
			if err
				callback err
			else
				db = database
				db.view 'tickets/open', {key: "systems"}, (err,doc) ->
					console.dir doc
				db.view 'tickets/open', {key: "support"}, (err,doc) ->
					console.dir doc
				callback null

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