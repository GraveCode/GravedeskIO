## routes

module.exports = (app, passport) ->

	ensureAuthenticated = (req, res, next) ->
		return next()  if req.isAuthenticated()
		res.redirect "/auth/google"

	# standard pages
	app.get "/", (req, res) ->
		#res.render "index",
		#	user: req.user
		res.send "index page goes here"
	
	app.get "/auth/account", ensureAuthenticated, (req, res) ->
		#res.render "account",
		#	user: req.user
		res.send "Welcome, " + req.user.displayName
		console.log req.user.emails[0].value + " logged in."
	
	
	app.get "/auth/google", passport.authenticate("google",
		failureRedirect: "/auth/google"
	), (req, res) ->
		res.redirect "/"
	
	app.get "/auth/google/return", passport.authenticate("google",
		failureRedirect: "/auth/google"
	), (req, res) ->
		# will always redirect to here first when logged in
		res.redirect "/auth/account"
	
	app.get "/auth/logout", (req, res) ->
		req.logout()
		res.redirect "/"
		