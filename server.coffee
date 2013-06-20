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
				# example queries
				#db.view 'tickets/open', { startkey: [settings.groups[0]], endkey: [settings.groups[0],{}] } , (err,docs) ->
				#	console.dir docs
				#db.view 'tickets/count', { startkey: [settings.groups[0]], endkey: [settings.groups[0],{}], reduce: true} , (err,docs) ->
				#	console.dir docs
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