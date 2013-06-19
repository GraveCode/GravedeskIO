async = require 'async'
cradle = require 'cradle'

addViews = (db, cb) ->
	cb null


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