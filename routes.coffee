path = require 'path'
fs = require 'fs'
crypto = require 'crypto'

## routes

module.exports = (app, passport, emailhandler, db, settings) ->

	ensureAuthenticated = (req, res, next) ->
		return next()  if req.isAuthenticated()
		res.redirect "/login/"

	# standard pages
	app.get "/node/", (req, res) ->
		res.send "GravedeskIO is running"
	
	app.get "/node/getuser", ensureAuthenticated, (req, res) ->
		res.send req.user

	app.get "/node/google", passport.authenticate("google",
		scope: ["https://www.googleapis.com/auth/userinfo.profile", "https://www.googleapis.com/auth/userinfo.email"]
	), (req, res) ->
		# The request will be redirected to Google for authentication, so this
		# function will not be called.

	app.get "/node/file/:id/:name", (req, res) ->
		id = req.params.id
		name = req.params.name
		if id and name
			readStream = db.getAttachment(id, name, (err) ->
				if err
					console.log err
				return
			)
			readStream.pipe(res)
		else
			res.send "Need an ID and filename!"

	app.post "/node/file/", (req, res) ->
		if req.files.upload
			idData = 
				id: req.body.id
				rev: req.body.rev

			attachmentData = 
				name: req.files.upload.name
				'Content-Type': req.files.upload.type

			readStream = fs.createReadStream req.files.upload.path
			writeStream = db.saveAttachment idData, attachmentData, (err, reply) ->
				if err
					console.log err
					return
			readStream.pipe writeStream
			res.redirect 'back'
		else 
			res.send "No upload received!"


	app.get "/node/google/return", passport.authenticate("google",
		failureRedirect: "/login/"
	), (req, res) ->
		# test if admin user
		user = req.user.emails[0].value
		i = settings.admins.indexOf user
		if i >= 0
			# admin user found
			res.redirect "/manage/"
		else
			res.redirect "/"

	
	app.get "/node/logout", (req, res) ->
		req.logout()
		res.redirect "https://accounts.google.com/Logout"

	# email restful API

	# receive notice of new mail from contextio
	app.post '/node/email/new', (req, res) ->
		console.log "new mail notification received"
		signer = crypto.createHmac('sha256', settings.contextIO.secret)
		if req.body?.timestamp and req.body?.token
			expected = signer.update(req.body?.timestamp + req.body?.token).digest('hex')
			if expected == req.body.signature
				# valid notice, retrieve message
				emailhandler.flagMessage req.body.message_data.message_id
		res.end()

	# receive failure notice of webhook
	app.post '/node/email/failed', (req, res) ->
		console.log "email retrieval failure: "
		console.log req.body
		res.end()

