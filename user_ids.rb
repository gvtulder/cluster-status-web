require "rubygems"
require "json"

class UserIDs
  DB_DIR = File.join(File.dirname(__FILE__), "db")

  def initialize(filename="qstat-user-to-ids.json")
    @filename = File.join(DB_DIR, filename)
    load_cache
  end

  def load_cache
    @cache = {}
    if File.exists?(@filename)
      @cache = (JSON.load(File.read(@filename)) rescue {})
    end
  end

  def write_cache
    File.open(@filename, "w") do |f|
      f << JSON.dump(@cache)
    end
  end

  def user_to_id(name)
    @cache[name] or (
      id = @cache.size
      @cache[name] = id
      write_cache
      id
    )
  end
end

