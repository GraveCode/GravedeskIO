module.exports = {
	# couch db settings
	couchdb: {
		dbServer: 'localhost'
		dbPort: 5984
		dbName: 'test'
		dbUser: 'admin'
		dbPass: 'password'
		# create up to date couchdb views at every server start
		overwriteViews: false
		cache: true
	}

	# default local app port
	defaultport: 3000
	# client facing url
	clientURL: 'http://example.com'
	clientID: 'google-client-id'
	clientSecret: 'google-client-secret'

	admins: [
		"user1@example.com"
		"user2@example.com"
	]

	serverEmail: 
		email: "gravedesk@example.com"
		name: "Gravedesk Support"

}