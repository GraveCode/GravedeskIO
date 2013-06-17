## routes

module.exports = (app) ->
	# standard pages
	app.get '/', (req, res) ->
		res.send ('Hello World')