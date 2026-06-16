# command_parser.rb
# encoding: UTF-8
require_relative 'professor_command_parser'

module CommandParser
  def self.parse(mastodon_client, sheet_manager, notification)
    reply_cb = lambda do |content, in_reply_to_id|
      mastodon_client.post_status(content, reply_to_id: in_reply_to_id, visibility: 'unlisted')
    end
    ProfessorParser.parse(reply_cb, sheet_manager, notification)
  end
end
