# A worker's own memory of rendered fragments, by name. Each Soli worker thread keeps its
# own (I18n's per-thread table cache), so nothing is shared and nothing needs locking; an
# entry is only ever used after SQLite confirms its signature, so a stale one costs a miss.
class PageCache
  static def get(name)
    table = I18n.cached_table("__page_cache")
    table.nil? ? nil : table[name]
  end

  static def set(name, value)
    table = I18n.cached_table("__page_cache") ?? I18n.cache_table("__page_cache", {})
    table[name] = value
  end

  # set, keeping at most limit entries of group: the oldest is dropped first.
  static def set_bounded(name, value, group, limit)
    table = I18n.cached_table("__page_cache") ?? I18n.cache_table("__page_cache", {})
    order_name = "__order:" + group
    order = table[order_name] ?? []
    order = order.filter { |n| n != name } unless table[name].nil?
    order.push(name)
    while order.length > limit
      table[order[0]] = nil
      order = order.drop(1)
    end
    table[order_name] = order
    table[name] = value
  end
end
