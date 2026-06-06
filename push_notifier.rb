# /root/mastodon_bots/professor_bot/push_notifier.rb

module PushNotifier
  def self.broadcast(mastodon_client, message)
    return if message.nil? || message.strip.empty?

    begin
      mastodon_client.broadcast(message)
      puts "[PushNotifier] 전송 성공: #{message[0..40]}..."
    rescue => e
      puts "[PushNotifier] 전송 실패: #{e.message}"
    end
  end
end
