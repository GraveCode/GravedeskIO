## modules & variables

settings = require './settings'
dbinit = require './lib/dbinit'
express = require 'express'
async = require 'async'


passport = require 'passport'
GoogleStrategy = require('passport-google').Strategy

db = null

# passport requirements

passport.serializeUser (user, done) ->
	done null, user

passport.deserializeUser (obj, done) ->
	done null, obj

passport.use new GoogleStrategy(
	returnURL: "https://gravedeskdev.clayesmore.com/auth/google/return"
	realm: "https://gravedeskdev.clayesmore.com/"
, (identifier, profile, done) ->
	process.nextTick ->
		profile.identifier = identifier
		done null, profile
)

app = express()

app.configure ->
	app.set "views", __dirname + "/views"
	app.set "view engine", "jade"
	#app.use express.logger()
	app.use express.cookieParser()
	app.use express.bodyParser()
	app.use express.methodOverride()
	app.use express.session(secret: "keyboard cat")
	app.use passport.initialize()
	app.use passport.session()
	app.use app.router
	app.use express.static(__dirname + "/public")

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