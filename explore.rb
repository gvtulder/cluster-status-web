require "sinatra"

class Stats
  STATS = %w{ timestamp job_number task_number owner job_name vmem_request cpu mem io iow vmem maxvmem }
  #              0          1         2         3      4         5          6   7  8  9   10    11

  def initialize(filename)
    @filename = filename
    load_from_file
  end

  def stale?
    File.mtime(@filename) > @timestamp
  end

  def refresh
    load_from_file if stale?
    self
  end

  def [](job_id)
    @all_job_stats[job_id].reverse
  end

  def each
    @last_job_stats.reverse_each do |job_id, job|
      yield job_id, job
    end
  end

  private

  def load_from_file
    @timestamp = File.mtime(@filename)

    all_job_stats = Hash.new{|h,k|h[k] = []}
    last_job_stats = {}
    File.open(@filename) do |f|
      f.each_line do |line|
        parts = line.strip.split("\t")
        if parts[0] =~ /^[0-9]+$/
          # line with a job
          job_id = "#{ parts[1] }.#{ parts[2] }"
          all_job_stats[job_id] << parts
          last_job_stats[job_id] = parts
        end
      end
    end

    @all_job_stats = all_job_stats
    @last_job_stats = last_job_stats
  end
end

def format_mem(mem)
  (mem.to_f.to_i / (1024*1024)).to_s.reverse.gsub(/(...)(?=.)/, "\\1.").reverse
end

before do
  cache_control :public, :must_revalidate, :max_age => 10
end

helpers do
  def h(text)
    Rack::Utils.escape_html(text)
  end
end

STATS_CACHE = Hash.new do |h,dt|
  h[dt] = Stats.new("csv-mem/#{ dt }.csv")
end
def purge_cache
  STATS_CACHE.keys.select do |dt|
    STATS_CACHE[dt].stale?
  end.each do |dt|
    STATS_CACHE.delete(dt)
  end
end

get "/" do
  dates = Dir["csv-mem/*.csv"].map do |f| f[/[0-9]+[-0-9]+/] end
  erb :index, :locals=>{ :dates=>dates }
end

get "/:date/" do |date|
  raise "Invalid date" unless date=~/\A[-0-9]+\Z/
  stats = STATS_CACHE[date].refresh
  purge_cache
  erb :list_tasks, :locals=>{ :date=>date, :stats=>stats, :current_job=>nil }
end

get "/:date/:job_id" do |date, job_id|
  raise "Invalid date" unless date=~/\A[-0-9]+\Z/
  stats = STATS_CACHE[date].refresh
  purge_cache
  erb :list_tasks, :locals=>{ :date=>date, :stats=>stats, :current_job=>job_id }
end

