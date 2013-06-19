async = require 'async'
cradle = require 'cradle'

designs = ['tickets', 'messages']


addViews = (db, cb) ->
	async.series([
		(callback) ->
			# delete listed designs in case they've changed views
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

			async.forEach designs, deleteDesign, callback

			# now we have a clean slate to add the new design documents
		, (callback) ->
				ticketViews = {
					"open":
						map: (doc) -> emit doc.group, doc if !doc.closed and doc.type is 'ticket'

					"closed":
						map: (doc) -> emit doc.modified, doc if doc.closed and doc.type is 'ticket'
				}

				db.save '_design/tickets', ticketViews, callback

	], cb)


module.exports = (couchdb, callback) ->
	c = new (cradle.Connection)(couchdb.dbServer, couchdb.dbPort,
			cache: true
			raw: false
		)
	db = c.database couchdb.dbName

	# couchdb connection
	db.exists (err, exists) ->
		if err
			callback err
		else if exists
			# db exists, callback with db
			console.log 'Connected to database "' + couchdb.dbName + '" on ' + couchdb.dbServer
			addViews db, (err) ->
				callback err, db
		else
			db.create()
			console.log 'Created database ' + couchdb.dbName + ' on ' + couchdb.dbServer
			addViews db, (err) ->
				callback err, db