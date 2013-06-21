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

require('./routes')(app, passport)

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
  socket.emit 'news', "Hello, " + socket.handshake.user.displayName
  console.log socket.handshake.user.displayName + " has connected."









