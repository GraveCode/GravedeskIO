async = require 'async'
cradle = require 'cradle'
designs = ['tickets', 'messages']

addViews = (db, cb) ->
	async.series([
		# delete listed designs in case they've changed views
		(callback) ->
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

			# order must match that of designs array
			newdesigns = [
				# ticket views
				{	
					open:
						map: "function(doc) {if (!doc.closed && doc.type === 'ticket' && doc.group !== 0) {emit([doc.group, doc.priority, doc.modified], doc);}}"
						reduce: "_count"

					closed:
						map: "function(doc) {if (doc.closed && doc.type === 'ticket' && doc.group !== 0) {emit([doc.group, doc.modified], doc);}}"
						reduce: "_count"

					personalopen:
						map: "function(doc) {if (!doc.closed && doc.type === 'ticket' && doc.group === 0) { emit([doc.personal, doc.priority, doc.modified], doc); } }"	
						reduce: "_count"

					personalclosed:
						map: "function(doc) {if (doc.closed && doc.type === 'ticket' && doc.group === 0)  { emit([doc.personal, doc.priority, doc.modified], doc); } }"	
						reduce: "_count"

					byuser:
						map: "function(doc) {if (doc.type === 'ticket') { for(var i=0, l=doc.recipients.length; i<l; i++) { emit([doc.recipients[i], doc.modified], doc); } } }"

				}
				# message views
				, { 
					all:
						map: "function(doc) {if (doc.type === 'message') {emit([doc.ticketid, doc.date], doc);}}"
					
					public:
						map: "function(doc) {if (doc.type === 'message' && !doc.private) {emit([doc.ticketid, doc.date], doc);}}" 	

					ids:
						map: "function(doc) {if (doc.type === 'message') {emit(doc.ticketid, {id: doc._id, rev: doc._rev});}}"	

				}
			]

			saveDesign = (design, subcallback) ->
				designName = '_design/'+design
				i = designs.indexOf design
				console.log "Saving design for " + designName
				db.save designName, newdesigns[i], subcallback				

			async.forEach designs, saveDesign, callback

	# and pass back any errors to the callback			
	], cb)


# main function exported to server.coffee
module.exports = (couchdb, callback) ->
	c = new(cradle.Connection)(couchdb.dbServer, couchdb.dbPort,
			cache: couchdb.cache
			raw: false
			auth:
				username: couchdb.dbUser 
				password: couchdb.dbPass
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
			# remove old view data
			db.viewCleanup()
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


