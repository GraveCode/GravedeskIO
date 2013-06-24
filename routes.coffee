## routes

module.exports = (app, passport) ->

	ensureAuthenticated = (req, res, next) ->
		return next()  if req.isAuthenticated()
		res.redirect "/node/google"

	# standard pages
	app.get "/", (req, res) ->
		res.send "GravedeskIO is running"
	
	app.get "/node/testaccount", ensureAuthenticated, (req, res) ->
		res.send "Welcome, " + req.user.displayName
	
	app.get "/node/google", passport.authenticate("google",
		failureRedirect: "/node/google"
	), (req, res) ->
		res.redirect "/"
	
	app.get "/node/google/return", passport.authenticate("google",
		failureRedirect: "/node/google"
	), (req, res) ->
		# console.log req.user.emails[0].value + " logged in."
		# will always redirect to here first when logged in
		res.redirect "/"
	
	app.get "/node/logout", (req, res) ->
		req.logout()
		res.redirect "/"
