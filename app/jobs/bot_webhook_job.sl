# Bot::WebhookJob: one bot's webhook for one message (see Bots).
class BotWebhookJob
  static def perform(args)
    bot = User.find_active_bot(args["bot_id"])
    message = Message.find_hash(args["message_id"])
    return nil if bot.nil? || message.nil?

    Bots.deliver(bot, message, args["base_url"])
  end
end
