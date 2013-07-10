module.exports = {
	# couch db settings
	couchdb: {
		dbServer: 'http://localhost'
		dbPort: 5984
		dbName: 'test'
		dbUser: 'admin'
		dbPass: 'password'
		# create up to date couchdb views at every server start
		overwriteViews: false
	}

	# default local app port
	defaultport: 3000
	# client facing url
	clientURL: 'http://example.com'

	admins: [
		"user1@example.com"
		"user2@example.com"
	]

	serverEmail: 
		email: "gravedesk@example.com"
		name: "Gravedesk Support"

}