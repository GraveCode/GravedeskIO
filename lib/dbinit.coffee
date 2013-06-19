async = require 'async'
cradle = require 'cradle'

addViews = (db, cb) ->
	async.series([
		# delete listed designs in case they've changed views
		(callback) ->
			designs = ['tickets', 'messages', 'autoreplies']
			deleteDesign = (design, subcallback) ->
				designName = '_design/'+design
				db.get designName, (err, doc) ->
					if err
						# design does not exist, we're done here
						subcallback null
					else if doc._rev
						# remove design
						db.remove designName, doc._rev, subcallback
					else
						subcallback "Problem deleting design: " + doc

			# delete design document for each design in tesigns array
			async.forEach designs, deleteDesign, callback

		# now we have a clean slate to add the new design documents
		, (callback) ->
			# views for tickets
			ticketsViews = {
				"open":
					map: (doc) -> emit doc.group, doc if !doc.closed and doc.type is 'ticket'

				"closed":
					map: (doc) -> emit doc.modified, doc if doc.closed and doc.type is 'ticket'
			}
			# save the tickets design document to the database
			db.save '_design/tickets', ticketsViews, callback

		, (callback) ->
			# views for autoreplies
			autorepliesViews = {
				"all":
					map: (doc) -> emit doc.ticketid, doc if doc.type is 'autoreply'
			}
			# save the autoreplies design document to the database
			db.save '_design/autoreplies', autorepliesViews, callback

		, (callback) ->
			# views for messages
			messagesViews = {
				"all":
					map: (doc) -> emit doc.ticketid, doc if doc.type is 'message'
			}
			# save the messages design document to the database
			db.save '_design/messages', messagesViews, callback

	# and pass back any errors to the callback			
	], cb)

# main function exported to server.coffee
module.exports = (couchdb, callback) ->
	c = new(cradle.Connection)(couchdb.dbServer, couchdb.dbPort,
			cache: false
			raw: false
		)
	db = c.database couchdb.dbName

	# couchdb connection
	db.exists (err, exists) ->
		# check we can connect to database!
		if err
			callback err
		else if exists
			# db exists, so 
			# add design document views, and return db object
			console.log 'Connected to database "' + couchdb.dbName + '" on ' + couchdb.dbServer
			# check if we wish to create views 
			if couchdb.overwriteViews
				console.log "Adding design documents"
				addViews db, (err) ->
					callback err, db
			else 
				callback null, db

		else
			# db doesn't exist yet, so we create it and add the design document views
			db.create()
			console.log 'Created database ' + couchdb.dbName + ' on ' + couchdb.dbServer
			console.log "Adding design documents"
			addViews db, (err) ->
				callback err, db


