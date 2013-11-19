require "rubygems"
require "json"

class UserIDs
  DB_DIR = File.join(File.dirname(__FILE__), "db")

  def initialize(filename="qstat-user-to-ids.json", save_on_changes=true)
    @filename = File.join(DB_DIR, filename)
    @save_on_changes = save_on_changes
    load_cache
  end

  def load_cache
    @cache = {}
    if File.exists?(@filename)
      @cache = (JSON.load(File.read(@filename)) rescue {})
    end
  end

  def write_cache
    if @save_on_changes
      File.open(@filename, "w") do |f|
        f << JSON.dump(@cache)
      end
    end
  end

  def user_to_id(name)
    name = name.to_s.downcase.delete("^a-z")
    @cache[name] or (
      # find an unused id
      ids_used = @cache.values
      id = 0
      while ids_used.include?(id)
        id += 1
      end

      # assign id
      @cache[name] = id
      write_cache
      id
    )
  end
end

