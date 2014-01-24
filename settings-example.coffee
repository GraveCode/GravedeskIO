module.exports = {
	# couch db settings
	couchdb: {
		server: '127.0.0.1'
		port: 5984
		name: 'test'
		user: 'admin'
		pass: 'password'
		# create up to date couchdb views at every server start
		overwriteViews: false
		cache: true
	}

	# redis session store
	redisdb: {
		server: '127.0.0.1'
		port: 6379
	}

	# default local app port
	defaultport: 3000
	# client facing url
	clientURL: 'http://www.example.com'
	# google oauth2 authentication settings
	clientID: '12345.apps.googleusercontent.com'
	clientSecret: 'secret'
	# restrict logins to only allow from a specific google hosted domain if set
	clientDomain: ''

	# maximum allowed messages on a single ticket (anti-spam measure)
	maxMessages: 200


	# context.io settings for reading mail tickets
	contextIO: {
		# oauth key and id
		key: "12345"
		secret: "secret"
		# maibox id (optional) for account on context.io
		id: "0123456789abcde"
		# mailbox account address set on context.io
		email: "itsupport@example.com"
		# mailbox that incoming mails will be read from
		inbox: "INBOX"
		# mailbox that processed mails will be moved to
		endbox: "processed"
		# force replace webhooks every server start
		overwriteWebhooks: false
	}

	# users with full access to ticket management
	admins: [
		"bill@example.com"
		"ben@example.com"
	]

	# users with limited ability to reply to tickets
	techs: [
		"weed@example.com"
	]

	# settings for outbound mail
	serverEmail: 
		# email and name that email will be sent as
		email: "itsupport@example.com"
		name: "IT Support"
		#outbound authentication settings, format for nodemailer
		smtpServer:	{
			"service": "Gmail"
			"auth": { 
				"user": "itsupport@example.com"
				"pass": "password"
			}
		}
		# block autoreplies going to email addresses other than that of the listed domain
		blockNonDomain: false
		# ignored if blockNonDomain is set false
		allowDomain: "example.com"

	# visible groups on the management view
	groups: ["IT Support", "Network & Systems", "Long term", "Software Dev"]
}

