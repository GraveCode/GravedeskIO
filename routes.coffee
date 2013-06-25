## routes

module.exports = (app, passport, settings) ->

	ensureAuthenticated = (req, res, next) ->
		return next()  if req.isAuthenticated()
		res.redirect "/node/google"

	# standard pages
	app.get "/", (req, res) ->
		res.send "GravedeskIO is running"
	
	app.get "/node/getuser", (req, res) ->
		res.send req.user
	
	app.get "/node/google", passport.authenticate("google",
		failureRedirect: "/node/google"
	), (req, res) ->
		res.redirect "/"
	
	app.get "/node/google/return", passport.authenticate("google",
		failureRedirect: "/node/google"
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
		res.redirect "/"

	app.get "/node/settings", ensureAuthenticated, (req, res) ->
		res.send settings.clientConfig

