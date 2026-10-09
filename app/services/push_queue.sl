# Room::PushMessageJob, queued in SQLite: a message's push goes in the push_queue table (one
# cheap write) and PushDeliveryJob drains it every couple of seconds. Unlike the Go and Rust
# ports' in-process queues, it survives a restart of the app.
class PushQueue
  # Without VAPID keys nothing could be delivered, so nothing is queued.
  static def enqueue(item)
    return nil unless WebPush.configured?

    Db.exec("INSERT INTO push_queue (item) VALUES (?)", [item])
  end

  # Without VAPID keys nothing can be delivered, so the queue is just emptied.
  static def drain(limit = 500)
    unless WebPush.configured?
      Db.exec("DELETE FROM push_queue")
      return nil
    end

    taken = Db.exec("DELETE FROM push_queue WHERE id IN (SELECT id FROM push_queue ORDER BY id LIMIT ?) RETURNING id, item",
                    [limit])
    ordered = taken.sort_by { |r| r["id"] }
    for row in ordered
      item = json_parse(row["item"]) rescue nil
      MessagePusher.push(item) unless item.nil?
    end
  end
end
