require "sinatra"

set :environment, :production

class Stats
  STATS = %w{ timestamp job_number task_number owner job_name vmem_request cpu mem io iow vmem maxvmem job_project }
  #              0          1         2         3      4         5          6   7  8  9   10    11       12

  def initialize(filename)
    @filename = filename
    @last_pos = 0
    @all_job_stats = Hash.new{|h,k|h[k] = []}
    @last_job_stats = {}
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
    JobStats.new(job_id, (@all_job_stats[job_id] || []))
  end

  def current_jobs
    latest_date = @last_job_stats.map do |job_id, job|
      job[0]
    end.max
    jobs = []
    self.each do |job_id, job|
      jobs << [job_id, job] if job[0] == latest_date
    end.sort_by do |job_id, job|
      job_id.split(".").map(&:to_i)
    end
    jobs
  end

  def each
    @last_job_stats.sort_by do |job_id, job|
      [ job[0], *job_id.split(".").map(&:to_i) ]
    end.reverse_each do |job_id, job|
      yield job_id, job
    end
  end

  private

  def load_from_file
    @timestamp = File.mtime(@filename)

    $stderr.puts "Parsing #{ @filename } from #{ @last_pos }"

    File.open(@filename) do |f|
      f.pos = @last_pos
      while line = f.gets
        cur_pos = f.pos
        if line.end_with?("\n")
          @last_pos = cur_pos
          parts = line.strip.split("\t")
          if parts[0] =~ /^[0-9]+$/
            # line with a job
            job_id = "#{ parts[1] }.#{ parts[2] }"
            @all_job_stats[job_id] << parts
            @last_job_stats[job_id] = parts
          end
        end
      end
    end

    $stderr.puts "Parsed #{ @filename } up to #{ @last_pos }"
  end

  class JobStats
    include Enumerable

    def initialize(job_id, stats)
      @job_id = job_id
      @stats = stats
    end

    def each
      @stats.reverse_each do |job|
        yield @job_id, job
      end
    end
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

def previous_date(dt)
  dt = (Date.parse(dt) - 1).strftime("%Y-%m-%d")
  File.exists?("csv-mem/#{ dt }.csv") ? dt : nil
end
def next_date(dt)
  dt = (Date.parse(dt) + 1).strftime("%Y-%m-%d")
  File.exists?("csv-mem/#{ dt }.csv") ? dt : nil
end

STATS_CACHE = Hash.new do |h,dt|
  h[dt] = Stats.new("csv-mem/#{ dt }.csv")
end
def purge_cache
  # TODO
# STATS_CACHE.keys.select do |dt|
#   STATS_CACHE[dt].stale?
# end.each do |dt|
#   STATS_CACHE.delete(dt)
# end
end

get "/" do
  dates = Dir["csv-mem/*.csv"].map do |f| f[/[0-9]+[-0-9]+/] end
  date = dates.sort.last
  stats = STATS_CACHE[date].refresh
  erb :list_tasks, :locals=>{ :running=>true, :date=>date, :stats=>stats.current_jobs, :current_job=>nil, :dates=>dates }
end

get "/history" do
  dates = Dir["csv-mem/*.csv"].map do |f| f[/[0-9]+[-0-9]+/] end
  erb :index, :locals=>{ :dates=>dates }
end

get "/:date/" do |date|
  dates = Dir["csv-mem/*.csv"].map do |f| f[/[0-9]+[-0-9]+/] end
  raise "Invalid date" unless dates.include?(date)
  stats = STATS_CACHE[date].refresh
  purge_cache
  erb :list_tasks, :locals=>{ :running=>false, :date=>date, :stats=>stats, :current_job=>nil, :dates=>dates }
end

get "/:date/:job_id" do |date, job_id|
  dates = Dir["csv-mem/*.csv"].map do |f| f[/[0-9]+[-0-9]+/] end
  raise "Invalid date" unless dates.include?(date)
  stats = STATS_CACHE[date].refresh
  purge_cache
  erb :list_tasks, :locals=>{ :running=>false, :date=>date, :stats=>stats[job_id], :current_job=>job_id, :dates=>dates }
end

