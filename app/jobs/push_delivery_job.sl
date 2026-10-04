# Delivers the push notifications queued by PushQueue (scheduled in config/application.sl).
class PushDeliveryJob
  static def perform(args)
    PushQueue.drain
  end
end
