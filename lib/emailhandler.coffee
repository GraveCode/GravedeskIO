# required modules
{EventEmitter} = require "events" 
async = require "async"
marked = require "marked"
contextio = require "contextio"
nodemailer = require "nodemailer"

marked.setOptions(
	gfm: true
	breaks: true
	smartypants: true
	sanitize: true
)

class EmailHandler extends EventEmitter
	constructor: (@joint, @db, @lang, @settings) ->
		# define smtp server transport
		@smtpTransport = nodemailer.createTransport "SMTP", @settings.serverEmail.smtpServer
		# define context IO client 
		@ctxioClient = new contextio.Client '2.0', 
			key: @settings.contextIO.key 
			secret: @settings.contextIO.secret
		# variables for contextIO account
		@ctxioID = ""
		@ctxioemail = ""
		# starting timestamp
		@timestamp = 1
		## control flow
		# call sync and trigger a full mailbox check when ID retrieved
		@on "getIDSuccess", @_sync
		@on "getIDSuccess", @_listMessages
		@on "getIDSuccess", @_setWebhook
		# call sync when prompted by timeout
		@on "doSync", @_sync
		# call list when prompted by timeout
		@on "doList", @_listMessages
		# after messages listed, check to see which are unread
		@on "listMessagesSuccess", @_filterNewMessages
		# filtered list of new messages found, ask to be flagged and processed
		@on "filterNewMessagesSuccess", @_checkNewMessages
		# marked as read ok, now get message
		@on "flagMessageSuccess", @_getMessage
		# message read ok, now get any attachments
		@on "getMessageSuccess", @_getMessageAttachments
		# attachments retrieved, now process
		@on "getMessageAttachmentsSuccess", @_processMessage 
		# message pared down to only required info, hand off to create ticket
		@on "processMessageSuccess", @joint.emailToTicket
		# ticket added to db, move original message
		@joint.on "emailToTicketSuccess", @_moveMessage 
		# ticket/message added to db, send autoreply
		@joint.on "autoReply", @_autoReply
		# autoreply allowed and formatted, send
		@on "autoReplySuccess", @sendMail

	# PUBLIC FUNCTIONS
	getID: (callback) =>
		self = @
		self.ctxioemail = self.settings.contextIO.email
		self.ctxioClient.accounts().get
			email: self.ctxioemail
			status_ok: 1
		, (err, response) ->
			if !err and response?.body.length > 0
				self.ctxioID = response.body[0].id 
				self.emit "getIDSuccess", self.ctxioID
				callback null
			else if self.settings.contextIO?.id
				# couldn't query contextIO account ID, going with one from settings, hope that contextIO starts working again
				console.log "Failed to retrieve working ContextIO account ID; continuing with saved one."
				self.ctxioID = self.settings.contextIO.id
				self.emit "getIDSuccess", self.ctxioID
				callback null
			else
				callback "Working ContextIO ID could not be found."

	
	flagMessage: (msgid) =>
		self = @
		# first, we flag as read to stop duplicate attempts on the same message
		self.ctxioClient.accounts(self.ctxioID).messages(msgid).flags().post
			seen: 1
		, (err, response) ->
			if err or !response.body.success
				self.emit "flagMessageError", err, msgid, response
			else
				self.emit "flagMessageSuccess", msgid

	sendMail: (mail) =>
		self = @
		self.smtpTransport.sendMail mail, (err, res) ->
			if err
				self.emit "smtpSendError", err, mail.to
			else
				self.emit "smtpSendSuccess", mail.to
	
	# INTERNAL FUNCTIONS

	_setWebhook: (id) =>
		self = @		

		async.waterfall([
			(cb) ->
				# get existing webhooks
				self.ctxioClient.accounts(id).webhooks().get (err, res) ->
					cb err, res

			, (res, cb) ->
				if res.body.length < 1
					# if no webhook, next step
					cb null, true
				else if self.settings.contextIO.overwriteWebhooks
					# if set to do webhooks every start, delete all existing
					console.log "Deleting webhooks"
					iterator = (webhook, callback) ->
						self.ctxioClient.accounts(id).webhooks(webhook.webhook_id).delete callback
	
					async.each res.body, iterator, (err, res) ->
						if err
							cb err
						else
							# all deleted, next step
							cb null, true

				else 
					cb null, false

			, (createWebhook, cb) ->	
				webhookSettings = 
					callback_url: self.settings.clientURL + "/node/email/new"
					failure_notif_url: self.settings.clientURL + "/node/email/failed"
					sync_period: "immediate"	
					filter_to: self.ctxioemail

				if createWebhook
					# create new webhook
					console.log "Creating webhook"				
					self.ctxioClient.accounts(id).webhooks().post webhookSettings, (err, res) ->
						cb err

				else
					# no need to create webhook
					cb null

			], (err, res) ->
				if err
					self.emit "setWebhookError", err, id
				else
					self.emit "setWebhookSuccess"
			)

	_sync: =>
		self = @
		# after 1 minute trigger the next sync
		setTimeout (->
			self.emit "doSync"
		), (60 * 1000)	

		# tell contextio to sync all mail records for account
		self.ctxioClient.accounts(self.ctxioID).sync().post (err, response) ->
			if err
				console.log err
				console.log response
				self.emit "SyncError", self.ctxioID
			self.emit "SyncSuccess" unless err

	_listMessages: =>
		self = @
		# after 5 minutes trigger the next full list check - this is just belt and braces 
		# the webhook should notify us of new messages as they occur
		setTimeout (->
			self.emit "doList"
		), (5 * 60 * 1000)	
		# get list of recent messages in inbox
		self.ctxioClient.accounts(self.ctxioID).messages().get
			"folder": self.settings.contextIO.inbox
			"indexed_after": self.timestamp
		, (err, response) ->
			if err
				console.log err
				console.log response
				self.emit "listMessagesError", "unable to find new messages: " + err
			else
				self.emit "listMessagesSuccess", response.body 

	_filterNewMessages: (list) =>
		self = @
		testIsRead = (msg, callback) ->
			# contextio doesn't save message flags, so each message will be checked against imap
			self.ctxioClient.accounts(self.ctxioID).messages(msg.message_id).flags().get (err, response) ->
				# in the event of an error, best to just ignore the message
				callback true if err
				# otherwise send back status of 'seen' flag 
				callback response.body.seen unless err

		async.reject list, testIsRead, (filteredlist) ->
			# results is now a list of unread message objects
			self.emit "filterNewMessagesSuccess", filteredlist

	_checkNewMessages: (list) =>
		self = @
		# for each new message, call to flag as read (and retrieve and process) on each message
		iterator = (msg, callback) ->
			self.flagMessage msg.message_id
			callback null
		async.forEach list, iterator, (err) ->
			self.emit "checkNewMessagesError" if err

	_getMessage: (msgid) =>
		self = @
		# retrieve email message context from contextio, with body retrieved on our behalf
		self.ctxioClient.accounts(self.ctxioID).messages(msgid).get
			include_body: 1
		, (err, response) ->
			if err 
				self.emit "getMessageError", err, msgid, response.body
			else
				# update timestamp to latest message indexed
				if self.timestamp < response.body.date_indexed
					self.timestamp = response.body.date_indexed
				self.emit "getMessageSuccess", msgid, response.body

	_getMessageAttachments: (msgid, msg) =>
		self = @
		retrieveFile = (fileHeader, callback) ->
			self.ctxioClient.accounts(self.ctxioID).files(fileHeader.file_id).content().get (err, filecontent) ->
				if err
					callback err
				else
					file = 
						"name": fileHeader.file_name
						"Content-Type": fileHeader.type
						"body": filecontent.body
					callback null, file

		if msg?.files
			async.mapSeries msg.files, retrieveFile, (err, results) ->
				if err 
					self.emit "getMessageAttachmentsError", err, msgid
				else
					self.emit "getMessageAttachmentsSuccess", msgid, msg, results
		else self.emit "getMessageAttachmentsSuccess", msgid, msg, []

	_processMessage: (msgid, msg, files) =>
		checkbodytype = (obj) ->
			if obj.type is "text/plain"
				form.rawtext += obj.content
			else if obj.type is "text/html"
				form.rawhtml += obj.content
			return null

		self = @
		form = 
			email: msg.addresses.from?.email or null
			name: msg.addresses.from?.name or null
			subject: msg?.subject or null
			rawtext: ""
			rawhtml: ""
		
		attachments = files or []
		checkbodytype obj for obj in msg.body
		self.emit "processMessageSuccess", msgid, form, attachments


	_moveMessage: (msgid) =>
		# move processed message to folder
		self = @
		self.ctxioClient.accounts(self.ctxioID).messages(msgid).folders().post
			add: self.settings.contextIO.endbox
			remove: self.settings.contextIO.inbox
		, (err, response) ->
			if err 
				self.emit "moveMessageError", err
			else
				self.emit "moveMessageSuccess"

	_autoReply: (ticketid, options) =>
		self = @

		async.waterfall([
			(cb) ->
				self.db.get ticketid, cb

			, (ticket, cb) ->
				# trim recipients to allowed list
				# clone recipients list
				recipients = ticket.recipients.slice(0)

				iterator = (item, callback) ->
					# return true if wish to discard address from recipients
					# check if sending to ourselves! (mail loop)
					if item.toLowerCase().search(self.settings.contextIO.email) >= 0
						callback true
					# if relay to external domains blocked
					else if self.settings.serverEmail.blockNonDomain
						# check if on allowed domain
						result = (item.toLowerCase().search(self.settings.serverEmail.allowDomain.toLowerCase()) >= 0)
						if result 
							# email includes allowed domain
							callback false
						else
							# email not in allowed domain
							callback true
					# no reason to block this address
					else
						callback false

				async.reject recipients, iterator, (result) ->
					if result.length > 0
						ticket.recipients = result
						# recipient addresses included at least one allowed
						cb null, ticket
					else
						cb "No valid addresses found to send to."

			, (ticket, cb) ->
				outmail =
					"from": self.settings.serverEmail.name + " <" + self.settings.serverEmail.email + ">"
					"to": ticket.recipients.join(",")				
					"subject": "RE: " + ticket.title + " - ID: <" + ticketid + ">"	

				link = "[online](" + self.settings.clientURL + "/messages/?id=" + ticketid + ")."

				# email processed as new ticket
				if options?.email and options?.isNew and options?.message
					sub = self.lang.replyHeader + self.lang.newTicket[0] + link + self.lang.newTicket[1]
					outmail.text =  marked(sub + options.message.text)
					outmail.html = marked(sub) + options.message.html

				# email processed as reply to open ticket
				else if options?.email and options?.message
					sub = self.lang.replyHeader + self.lang.existingReply[0] + link + self.lang.existingReply[1]
					outmail.text =  marked(sub + options.message.text)
					outmail.html = marked(sub) + options.message.html

				# message reply from admin
				else if options?.message
					outmail.text = self.lang.replyHeader + ticket.names[options.message?.from] + self.lang.adminReply[0] + link + self.lang.adminReply[1] + options.message?.text
					outmail.html = marked(outmail.text)

				# closed with custom reply
				else if options?.closing and options?.text and options?.name
					outmail.text = self.lang.customClose[0] + options.name + self.lang.customClose[1] + link + self.lang.customClose[2] + options.text
					outmail.html = marked(outmail.text)

				# closed with no reply
				else if options?.closing and options?.name
					outmail.text = self.lang.standardClose[0] + options.name + self.lang.standardClose[1] + link
					outmail.html = marked(outmail.text)
				else
					cb "Couldn't work out what type of autoreply to do! "
				
				cb null, outmail

		], (err, result) ->
				if err
					self.emit "autoReplyError", err, ticketid
				else			
					self.emit "autoReplySuccess", result
		)

module.exports = EmailHandler