require "rubygems"
require "sinatra"
require "time"
require "json"
require "sinatra"

require "./qstat_memstats"
require "./matlab"
require "./qstat"
require "./user_ids"
require "./history"

def format_mem(mem)
  (mem.to_f.to_i / (1024*1024)).to_s.reverse.gsub(/(...)(?=.)/, "\\1.").reverse
end

def previous_date(dt)
  dt = (Date.parse(dt) - 1).strftime("%Y-%m-%d")
  History.exists?(dt) ? dt : nil
end
def next_date(dt)
  dt = (Date.parse(dt) + 1).strftime("%Y-%m-%d")
  History.exists?(dt) ? dt : nil
end

class Cache
  def self.cached(key, max_age=60, &block)
    @@cache ||= {}
    (@@cache[key] ||= Cache.new(max_age)).cached(&block)
  end

  def initialize(max_age)
    @max_age = 60
  end

  def cached
    if @timestamp.nil? or (Time.now - @timestamp) > @max_age
      @timestamp = Time.now
      @cached_value = yield
    end
    @cached_value
  end
end

$QSTAT_USER_IDS = UserIDs.new



set :environment, :production

before do
  cache_control :public, :must_revalidate, :max_age => 10
end

helpers do
  def h(text)
    Rack::Utils.escape_html(text)
  end
end

get "/" do
  redirect "/queues"
end

get "/queues" do
  erb :queues
end

get "/queue-stats.json" do
  content_type :json
  Cache.cached :queue_stats do
    d = Qstat.jobs_per_queue($QSTAT_USER_IDS)
    JSON.dump({
      :datetime=>Time.now.localtime.strftime("%H:%M:%S"),
      :stats=>d
    })
  end
end

get "/matlab" do
  erb :matlab, :locals=>{ :toolboxes=>MatlabLicense.toolboxes, :only_content=>params[:only_content] }
end


## memory

get "/memory" do
  dates = History.available_dates
  date = dates.last

  job_stats = History.today do |history|
    history.running_jobs
  end
  erb :memory_tasks, :locals=>{
         :running=>true,
         :date=>date,
         :stats=>job_stats,
         :current_job=>nil,
         :dates=>dates
      }
end

get "/memory/:date/" do |date|
  dates = History.available_dates
  raise "Invalid date" unless dates.include?(date)
  job_stats = History.for_date(date) do |history|
    history.all_jobs
  end
  erb :memory_tasks, :locals=>{
         :running=>false,
         :date=>date,
         :stats=>job_stats,
         :current_job=>nil,
         :dates=>dates
      }
end

get "/memory/:date/:job_id.json" do |date, job_id|
  dates = History.available_dates
  raise "Invalid date" unless dates.include?(date)
  job_data, job_profile = nil, nil

  History.for_date(date) do |history|
    job_data = history.single_job(job_id)
    job_profile = history.single_job_profile(job_id)
  end

  job_profile_js = {}
  job_profile_js[:job_data] = {
    "job_id"=>job_data["job_id"],
    "timestamp"=>job_data["timestamp"].to_i,
    "job_number"=>job_data["job_number"],
    "task_number"=>job_data["task_number"],
    "owner"=>job_data["owner"],
    "job_name"=>job_data["job_name"],
    "vmem_request"=>job_data["vmem_request"].to_i,
    "cpu"=>job_data["cpu"].to_f,
    "mem"=>job_data["mem"].to_f,
    "io"=>job_data["io"].to_f,
    "iow"=>job_data["iow"].to_f,
    "vmem"=>job_data["vmem"].to_i,
    "maxvmem"=>job_data["maxvmem"].to_i,
    "job_project"=>job_data["job_project"].to_s.sub(/^p[0-9]+_/, "")
  }
  job_profile_js[:job_profile] = {}
  %w{ timestamp vmem maxvmem }.each do |resource|
    job_profile_js[:job_profile][resource] = job_profile.map do |line|
      line[resource].to_i
    end
  end

  content_type :json
  JSON.dump(job_profile_js)
end

get "/memory/:date/:job_id" do |date, job_id|
  dates = History.available_dates
  raise "Invalid date" unless dates.include?(date)
  job_data, job_profile = nil, nil
  History.for_date(date) do |history|
    job_data = history.single_job(job_id)
    job_profile = history.single_job_profile(job_id)
  end
  job_stats = job_profile.map do |prof|
    {}.merge(job_data).merge(prof)
  end.reverse
  erb :memory_tasks, :locals=>{
         :running=>false,
         :date=>date,
         :stats=>job_stats,
         :current_job=>job_id,
         :dates=>dates
      }
end


## CSS with user colors (for the queue view)
# iwanthue
# H 0 - 360
# C 0.3 - 1.7
# L 0.3 - 0.8
COLORS = %w{ #AA5567 #5D8A2A #437EA5
             #986D1B #B860A8 #41845C
             #B95937 #68643E #825682
             #83493E #2D6461 #8F6A6F
             #CA5080 #686921 #C64C5A
             #3C566E #355C37 #8E5E35
             #64787E #457A39 #74415B
             #8A69A9 #A2527C #6076AB
             #5F5375 #488579 #417F94
             #A36D93 #535254 #AD5A95 }
COLORS_CSS = 
  COLORS.each_with_index.map do |c,i|
    ".all-owners .owner-#{ i }, .only-owner-#{ i } .owner-#{ i } {background-color:#{ c } !important;}\n"
  end.join

get "/user-colors.css" do
  content_type :css
  COLORS_CSS
end


## static files

get "/reset.css" do
  content_type :css
  File.read("public/reset.css")
end

get "/cluster.css" do
  content_type :css
  File.read("public/cluster.css")
end

get "/queues.js" do
  content_type :js
  File.read("public/queues.js")
end

get "/memory.js" do
  content_type :js
  Cache.cached :memory_js do
    File.read("public/memory.js")
  end
end


