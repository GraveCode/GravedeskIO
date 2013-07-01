## modules & variables

settings = require './settings'
dbinit = require './lib/dbinit'
express = require 'express'
async = require 'async'
path = require 'path'

passport = require 'passport'
passportSocketIO = require 'passport.socketio'
GoogleStrategy = require('passport-google').Strategy

db = null
app = express()


# passport requirements

passport.serializeUser (user, done) ->
	done null, user

passport.deserializeUser (obj, done) ->
	done null, obj

 
passport.use new GoogleStrategy(
	returnURL: settings.clientURL + "/node/google/return"
	realm: settings.clientURL
, (identifier, profile, done) ->
	process.nextTick ->
		profile.identifier = identifier
		done null, profile
)

MemoryStore = express.session.MemoryStore
sessionStore = new MemoryStore()

app.configure ->
	app.use express.cookieParser()
	app.use express.bodyParser()
	app.use express.methodOverride()
	app.use express.session(store: sessionStore, secret: 'tom thumb', key: 'express.sid')
	app.use passport.initialize()
	app.use passport.session()
	app.use app.router


# socket io setup

appserver = require('http').createServer(app)
io = require('socket.io').listen(appserver)
io.set 'resource', '/node/socket.io'
io.set 'log level', 1 # disable debug log
io.set "authorization", passportSocketIO.authorize(
	cookieParser: express.cookieParser #or connect.cookieParser
	key: "express.sid" #the cookie where express (or connect) stores its session id.
	secret: 'tom thumb' #the session secret to parse the cookie
	store: sessionStore #the session store that express uses
	fail: (data, accept) -> # *optional* callbacks on success or fail
		accept null, false # second param takes boolean on whether or not to allow handshake
	success: (data, accept) ->
		accept null, true
)


## routes

require('./routes')(app, passport, settings)

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
		# start express
		appserver.listen settings.defaultport
		console.log 'Listening on port ' + settings.defaultport
		callback null

], (err) ->
	# callback error handler
	if err
		console.log "Problem with starting core services; "
		console.log err
		process.exit err
)

## socket.io

io.sockets.on 'connection', (socket) ->
	user = socket.handshake.user
	console.log socket.handshake.user.displayName + " has connected."

	socket.on 'isAdmin', (callback) ->
		i = settings.admins.indexOf user.emails[0].value
		if i >= 0
			callback true
		else
			callback false

	socket.on 'getMyTickets', (user, callback) ->
		db.view 'tickets/mine', { descending: true, endkey: [[user]], startkey: [[user,{}],{}] } , (err, results) ->
			if !err
				open = []
				closed = []
				length = results.length
				element = null
				i = 0
				
				while i < length
					element = results[i]
					closed.push element if element.value.closed
					open.push element unless element.value.closed
					i++

				callback null, open, closed
			else
				callback err

	socket.on 'addTicket', (formdata, callback) ->
		timestamp = Date.now()
		async.waterfall([
			(cb) -> 
				ticket = 
					type: 'ticket'
					created: timestamp
					modified: timestamp
					title: formdata.subject
					status: 0
					closed: false
					group: +formdata.team
					recipients: [formdata.from]
				db.save ticket, (err, results) ->
					cb err, results, ticket

			, (results, ticket, cb) ->
				message = 
					type: 'message'
					date: timestamp
					from: formdata.from
					to: settings.serverEmail
					private: false
					body: formdata.description
					fromuser: true
					ticketid: results.id
				db.save message, (err, res) ->
					cb err, results, ticket
		], (err, results, ticket) ->
				if err 
					msg = 'Unable to save ticket to database! '
					console.log msg + err
					callback msg
				else
					msg = 'Ticket added to system. '
					console.log msg + 'Ticket id: ' + results.id
					socket.broadcast.emit('ticketAdded', results.id, ticket)
					callback null, msg
		)











