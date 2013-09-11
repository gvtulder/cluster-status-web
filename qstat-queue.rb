require "rubygems"
require "nokogiri"
require "time"
require "json"

class Nokogiri::XML::Node
  def text_at_xpath(xpath)
    el = at_xpath(xpath)
    el ? el.text : nil
  end
end

class QstatQueue
  def self.stats
    stats = Hash.new do |stats_hash, queue|
      stats_hash[queue] = Hash.new do |queue_hash, status|
        queue_hash[status] = []
      end
    end

    IO.popen(["qstat","-s","a","-u","*","-xml","-g","d","-r","-pri"]) do |io|
      doc = Nokogiri::XML(io)
      doc.xpath("//job_list").each do |job_list|
        job_number = job_list.text_at_xpath("JB_job_number")
        tasks = job_list.text_at_xpath("tasks")
        owner = job_list.text_at_xpath("JB_owner")
        state = job_list.text_at_xpath("state")
        job_name = job_list.text_at_xpath("JB_name")
        running_queue = job_list.text_at_xpath("queue")
        hard_req_queue = job_list.text_at_xpath("hard_req_queue")
        start_time = job_list.text_at_xpath("JAT_start_time")
        submission_time = job_list.text_at_xpath("JB_submission_time")
        prio = job_list.text_at_xpath("JAT_prio")

        queue = (running_queue || hard_req_queue)
        job_id = "#{ job_number }.#{ tasks || "1" }"

        unless job_name == "QRLOGIN"
          stats[queue][state] << {
            :job_id=>job_id,
            :owner=>owner,
            :prio=>prio,
            :job_number=>job_number,
            :job_name=>job_name
          }
        end
      end
    end

    stats.each_value do |queue_h|
      queue_h.each_value do |status_h|
        status_h.sort_by! do |job|
          - job[:prio].to_f
        end
      end
    end

    stats
  end
end

require "sinatra"

get "/stats.html" do
  <<EOHTML
<!DOCTYPE html>
<html>

<body>

<div id="container"></div>

<script type="text/javascript">

var stats = #{ JSON.dump(QstatQueue.stats) };

function summariseJobList(q) {
  var curBlock = null,
      blocks = [],
      job = null;
  for (var i=0; i<q.length; i++) {
    job = q[i];
    if (curBlock && curBlock.owner == job.owner) {
      curBlock.jobs.push(job);
    } else {
      curBlock = {
        owner: job.owner,
        jobs:  [ job ]
      };
      blocks.push(curBlock);
    }
  }
  return blocks;
}

function userJobGroup(jobGroup, maxJobs) {
  var div = document.createElement('div'),
      strong = document.createElement('strong'),
      span = document.createElement('span'),
      ul = document.createElement('ul'),
      li;
  div.appendChild(strong);
  div.appendChild(span);
  div.appendChild(ul);

  strong.appendChild(document.createTextNode(jobGroup.owner));
  span.appendChild(document.createTextNode('\u00D7 ' + jobGroup.jobs.length));

  var n = jobGroup.jobs.length;
  if (maxJobs && maxJobs < n) {
    n = maxJobs;
  }
  for (var i=0; i<n; i++) {
    li = document.createElement('li');
    li.appendChild(document.createTextNode(jobGroup.jobs[i].job_name));
    ul.appendChild(li);
  }
  return div;
}

var QUEUES = [ 'hour', 'day', 'week', 'month' ],
    STATES = [ 'qw', 'r' ]; 

var queuesUl = document.createElement('ul');

for (var q=0; q<QUEUES.length; q++) {
  var queue = QUEUES[q];
  for (var s=0; s<STATES.length; s++) {
    var state = STATES[s];
    if (stats[queue] && stats[queue][state]) {
      var li = document.createElement('li'),
          h2 = document.createElement('h2');
      h2.appendChild(document.createTextNode(queue + ' ' + state));
      li.appendChild(h2);
      queuesUl.appendChild(li);

      var jobGroups = summariseJobList(stats[queue][state]);
      for (var i=0; i<jobGroups.length; i++) {
        queuesUl.appendChild(userJobGroup(jobGroups[i], 5));
      }
    }
  }
}

var container = document.getElementById('container');
container.appendChild(queuesUl);

</script>

</body>
</html>

EOHTML
end

