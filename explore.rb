require "rubygems"
require "sinatra"
require "nokogiri"
require "time"
require "json"

set :environment, :production

require "./qstat_memstats"
require "./qstat_queue"
require "./matlab"

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
  h[dt] = MemoryStats.new("csv-mem/#{ dt }.csv")
end
def purge_cache
  # TODO
# STATS_CACHE.keys.select do |dt|
#   STATS_CACHE[dt].stale?
# end.each do |dt|
#   STATS_CACHE.delete(dt)
# end
end

require "sinatra"

$QSTAT_USER_IDS = UserIDs.new("qstat-user-to-ids.json")



get "/" do
  q = (request.query_string == "") ? "" : "?" + request.query_string
  redirect "/memory#{ q }"
end

get "/queues" do
  erb :queues
end

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
  File.read("public/memory.js")
end

get "/queue-stats.json" do
  content_type :json
  d = QstatQueue.stats($QSTAT_USER_IDS)
  JSON.dump({
    :datetime=>d[:timestamp].localtime.strftime("%H:%M:%S"),
    :stats=>d[:stats]
  })
end

# iwanthue
# H 0 - 360
# C 0.3 - 1.7
# L 0.3 - 0.8
COLORS = %w{ #AA5567
             #5D8A2A
             #437EA5
             #986D1B
             #B860A8
             #41845C
             #B95937
             #68643E
             #825682
             #83493E
             #2D6461
             #8F6A6F
             #CA5080
             #686921
             #C64C5A
             #3C566E
             #355C37
             #8E5E35
             #64787E
             #457A39
             #74415B
             #8A69A9
             #A2527C
             #6076AB
             #5F5375
             #488579
             #417F94
             #A36D93
             #535254
             #AD5A95 }

get "/user-colors.css" do
  content_type :css
# @user_colors_cache ||= (
#   [ 0, 16, 8, 24, 4, 12, 20, 28, 2, 6, 10, 14, 18, 22 ].flat_map do |offset|
#     [ 5 * offset, 5 * (offset + 30) ]
#   end.each_with_index.map do |h,i|
#     ".all-owners .owner-#{ i }, .only-owner-#{ i } .owner-#{ i } {background-color:hsl(#{ h },60%,35%) !important;}\n"
#   end.join
# )
#
  @user_colors_cache ||= (
    COLORS.each_with_index.map do |c,i|
      ".all-owners .owner-#{ i }, .only-owner-#{ i } .owner-#{ i } {background-color:#{ c } !important;}\n"
    end.join
  )
end

get "/matlab" do
  erb :matlab, :locals=>{ :toolboxes=>MatlabLicense.toolboxes, :only_content=>params[:only_content] }
end

get "/memory" do
  dates = Dir["csv-mem/*.csv"].map do |f| f[/[0-9]+[-0-9]+/] end
  date = dates.sort.last
  stats = STATS_CACHE[date].refresh
  erb :memory_tasks, :locals=>{ :running=>true, :date=>date, :stats=>stats.current_jobs, :current_job=>nil, :dates=>dates }
end

get "/history" do
  redirect "/memory/history"
end
get %r{\A(/[-0-9]+/.*)\Z} do
  q = (request.query_string == "") ? "" : "?" + request.query_string
  redirect "/memory#{ params[:captures].first }#{ q }"
end

get "/memory/history" do
  dates = Dir["csv-mem/*.csv"].map do |f| f[/[0-9]+[-0-9]+/] end
  erb :memory_history, :locals=>{ :dates=>dates }
end

get "/memory/:date/" do |date|
  dates = Dir["csv-mem/*.csv"].map do |f| f[/[0-9]+[-0-9]+/] end
  raise "Invalid date" unless dates.include?(date)
  stats = STATS_CACHE[date].refresh
  purge_cache
  erb :memory_tasks, :locals=>{ :running=>false, :date=>date, :stats=>stats, :current_job=>nil, :dates=>dates }
end

get "/memory/:date/:job_id" do |date, job_id|
  dates = Dir["csv-mem/*.csv"].map do |f| f[/[0-9]+[-0-9]+/] end
  raise "Invalid date" unless dates.include?(date)
  stats = STATS_CACHE[date].refresh
  purge_cache
  erb :memory_tasks, :locals=>{ :running=>false, :date=>date, :stats=>stats[job_id], :current_job=>job_id, :dates=>dates }
end

