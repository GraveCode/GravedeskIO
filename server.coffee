## modules & variables

settings = require './settings'
dbinit = require './lib/dbinit'
SocketHandler = require './lib/sockethandler'
EmailHandler = require './lib/emailhandler'
lang = require './lib/lang'
Joint = require './lib/joint'
express = require 'express'
async = require 'async'
path = require 'path'

passport = require 'passport'
passportSocketIO = require 'passport.socketio'
GoogleStrategy = require('passport-google-oauth').OAuth2Strategy

RedisStore = require('connect-redis')(express)

{EventEmitter} = require "events"

db = null
joint = null
app = express()


# passport requirements

passport.serializeUser (user, done) ->
	done null, user

passport.deserializeUser (obj, done) ->
	done null, obj

passport.use new GoogleStrategy(
	clientID: settings.clientID
	clientSecret: settings.clientSecret
	callbackURL: settings.clientURL + "/node/google/return"
, (accessToken, refreshToken, profile, done) -> 
	# asynchronous verification, for effect...
	process.nextTick ->
		done null, profile
)

sessionStore = new RedisStore

app.enable 'trust proxy'

app.configure ->
	app.use express.cookieParser()
	app.use express.json()
	app.use express.urlencoded()
	# this generates connect warning - waiting on express update!
	app.use express.multipart()
	app.use express.methodOverride()
	app.use express.session(store: sessionStore, secret: 'tom thumb')
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
	secret: 'tom thumb' #the session secret to parse the cookie
	store: sessionStore #the session store that express uses
	fail: (data, accept) -> # *optional* callbacks on success or fail
		accept null, false # second param takes boolean on whether or not to allow handshake
	success: (data, accept) ->
		accept null, true
)

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
		## routes
		require('./routes')(app, passport, settings, db)
		callback null

	, (callback) -> 
		# start express
		appserver.listen settings.defaultport
		console.log 'Listening on port ' + settings.defaultport
		callback null

	, (callback) ->
		# setup email server, get ID from context IO
		joint = new Joint(io.sockets, db, settings)
		emailhandler = new EmailHandler(joint, db, lang, settings)
		emailhandler.getID callback

		emailhandler.on "getIDSuccess", (id) -> console.log "ContextIO ID for " + settings.contextIO.email + " read as " + id
		emailhandler.on "smtpSendSuccess", (to) -> console.log "Mail successfully sent to " + to

		emailhandler.on "listMessagesError", (err) -> console.log err
		emailhandler.on "flagMessageError", (err, id, res) -> console.log "unable to flag contextio message " + id + "read, error: " + err + ": " + res
		emailhandler.on "getMessageError", (err, id, res) -> console.log "unable to retrieve contextio message " + id + ", error: " + err + ": " + res
		emailhandler.on "getMessageAttachmentsError", (err, id) -> console.log "unable to retrieve contextio attachments for message " + id + ", error: " + err
		emailhandler.on "SyncError", (err) -> console.log err
		emailhandler.on "smtpSendError", (err, to) -> console.log "Error sending mail to " + to + " : " + err
		emailhandler.on "autoReplyError", (err, id) -> console.log "Error sending autoreply for ticket " + id + ": " + err
		emailhandler.on "setWebhookError", (err, id) -> console.log "Error creating webhook for account " + id + ": " + err  


], (err) ->
	# callback error handler
	if err
		console.log "Problem with starting core services; "
		console.log err
		process.exit err
)

## socket.io

io.sockets.on 'connection', (socket) ->
	sockethandler = new SocketHandler(socket, db, joint, settings)


