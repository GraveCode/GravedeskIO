## routes

module.exports = (app, passport, settings) ->

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
		res.redirect "/loggedout/"

	app.get "/node/settings", ensureAuthenticated, (req, res) ->
		res.send settings.clientConfig

