# Room::PushMessageJob, queued in SoliKV: a message's push goes on a list (one cheap write)
# and PushDeliveryJob drains it every couple of seconds. Like the Go and Rust ports' in-process
# queues, a crash can lose what is queued; unlike them, it survives a restart of the app.
class PushQueue
  static KEY: String = "campfire:push_queue"

  static def enqueue(item)
    KV.rpush(PushQueue.KEY, json_stringify(item)) rescue nil
  end

  # Without VAPID keys nothing can be delivered, so the queue is just emptied.
  static def drain(limit = 500)
    unless WebPush.configured?
      KV.delete(PushQueue.KEY) rescue nil
      return nil
    end

    for i in 0..limit
      raw = KV.lpop(PushQueue.KEY) rescue nil
      break if raw.nil?

      item = JSON.parse(raw) rescue nil
      MessagePusher.push(item) unless item.nil?
    end
  end
end
