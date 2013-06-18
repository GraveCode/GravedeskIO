## modules & variables

settings = require './settings'
express = require 'express'
async = require 'async'
cradle = require 'cradle'
app = express()

c = new (cradle.Connection)(settings.dbServer, settings.dbPort,
			cache: true
			raw: false
		)
db = c.database settings.dbName

## routes

require("./routes")(app)

## start servers

async.series([
	(callback) ->
		# couchdb connection
		db.exists (err, exists) ->
			if err
				callback err
			else if exists
				console.log 'Connected to database "' + settings.dbName + '" on ' + settings.dbServer
				callback null
			else
				console.log 'Creating database ' + settings.dbName + ' on ' + settings.dbServer
				db.create()
				db.save "_design/tickets",
					open:
						map: (doc) ->
							if doc.type==="ticket" && !doc.closed
								emit doc.modified, doc
					closed: 
						map: (doc) ->
							if doc.type==="ticket" && doc.closed
								emit doc.modified, doc

				db.save "_design/messages",
					notprivate:
						map: (doc) ->
							if doc.type==="message" && !doc.closed && !private
								emit doc.date, doc
					open:
						map: (doc) ->
							if doc.type==="message" && !doc.closed
					closed: 
						map: (doc) ->
							if doc.type==="message" && doc.closed
								emit doc.date, doc

				db.save "_design/autoreplies",
					open:
						map: (doc) ->
							if doc.type==="autoreply" && !doc.closed
								emit doc.date, doc
					closed: 
						map: (doc) ->
							if doc.type==="autoreply" && doc.closed
								emit doc.date, doc


				# TODO: add design documents here
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