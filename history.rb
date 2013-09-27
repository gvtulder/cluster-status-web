require "rubygems"
require "time"
require "date"
require "sqlite3"

class History
  DB_DIR = File.join(File.dirname(__FILE__), "db")

  def self.available_dates
    dates = Dir["#{ DB_DIR }/*.sqlite3"].map do |f| f[/[0-9]+-[-0-9]+/] end
    dates.sort
  end

  def self.exists?(date)
    File.exists?("#{ DB_DIR }/#{ date }.sqlite3")
  end

  def self.today(&block)
    for_date(Time.now.strftime("%Y-%m-%d"), &block)
  end

  def self.for_date(date)
    # open database: csv-mem/YY-MM-DD.sqlite3
    r = nil
    SQLite3::Database.new("#{ DB_DIR }/#{ date }.sqlite3") do |db|
      db.busy_handler do |data, retries|
        # retry 30 times
        retries < 1000
      end
      # wait 200ms between tries
      db.busy_timeout(200)

      r = yield History.new(db)
    end
    r
  end

  def self.archive!(max_age=7)
    Dir["#{ DB_DIR }/*.sqlite3"].each do |f|
      if Date.parse(f[/[0-9]+-[-0-9]+/]) < Date.today - 7
        $stderr.puts "Archiving #{ f }"
        system(["gzip", f])
      end
    end
  end


  def initialize(db)
    @db = db
    create_tables
  end

  def running_jobs
    max_timestamp = @db.get_first_value("select max(timestamp) mt from jobs")
    @db.results_as_hash = true
    @db.execute("select * from jobs where timestamp = ? order by timestamp desc", max_timestamp)
  end

  def all_jobs
    @db.results_as_hash = true
    @db.execute("select * from jobs order by timestamp desc")
  end

  def single_job(job_id)
    @db.results_as_hash = true
    @db.get_first_row("select * from jobs where job_id = ?", job_id)
  end

  def single_job_profile(job_id)
    @db.results_as_hash = true
    @db.execute("select timestamp, cpu, mem, io, vmem, maxvmem from job_profiles where job_id = ? order by timestamp asc", job_id)
  end

  def store_job_stats(jobs, timestamp=nil)
    timestamp = Time.now.to_i if timestamp.nil?
    @db.transaction do
      # static job info
      @db.prepare("insert or replace into jobs values (?,?,?,?,?,?,?,?,?,?,?,?,?,?)") do |stmt|
        jobs.each do |job_number, job_data|
          job_data["tasks"].each do |task_number, task_data|
            stmt.execute([
              "#{ job_number }.#{ task_number }",
              timestamp,
              job_number,
              task_number,
              job_data["JB_owner"],
              job_data["JB_job_name"],
              job_data["vmem_request"],
              job_data["JB_project"],
              task_data["cpu"],
              task_data["mem"],
              task_data["io"],
              task_data["iow"],
              task_data["vmem"],
              task_data["maxvmem"]
            ])
          end
        end
      end

      # current resource stats
      @db.prepare("insert or replace into job_profiles values (?,?,?,?,?,?,?,?)") do |stmt|
        jobs.each do |job_number, job_data|
          job_data["tasks"].each do |task_number, task_data|
            stmt.execute([
              "#{ job_number }.#{ task_number }",
              timestamp,
              task_data["cpu"],
              task_data["mem"],
              task_data["io"],
              task_data["iow"],
              task_data["vmem"],
              task_data["maxvmem"]
            ])
          end
        end
      end
    end
  end

  private

  def create_tables
    @db.execute(%{
      create table if not exists jobs
        ( job_id, timestamp,
          job_number, task_number, owner, job_name, vmem_request, job_project,
          cpu, mem, io, iow, vmem, maxvmem,
          primary key (job_id) on conflict replace )
    })
    @db.execute(%{
      create table if not exists job_profiles
        ( job_id, timestamp,
          cpu, mem, io, iow, vmem, maxvmem,
          primary key (job_id, timestamp) on conflict replace )
    })
  end
end

