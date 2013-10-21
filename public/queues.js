(function(){

  function collectUsers(q, users, userProps) {
    for (var i=0; i<q.length; i++) {
      if (!userProps[q[i].owner])
        users.push(q[i].owner);
      userProps[q[i].owner] = {
        owner: q[i].owner,
        owner_id: q[i].owner_id
      };
    }
  }

  function summariseJobList(q, groupByOwner, reverseGroup) {
    var blocks = [], blocksPerOwner = {},
        curBlock, job;
    for (var i=0; i<q.length; i++) {
      if (reverseGroup) {
        job = q[q.length - i - 1];
      } else {
        job = q[i];
      }
      if (groupByOwner) {
        if (!blocksPerOwner[job.owner]) {
          curBlock = {
            owner: job.owner,
            owner_id: job.owner_id,
            jobs:  [ job ]
          };
          blocksPerOwner[job.owner] = curBlock;
          if (reverseGroup) {
            blocks.unshift(curBlock);
          } else {
            blocks.push(curBlock);
          }
        } else {
          if (reverseGroup) {
            blocksPerOwner[job.owner].jobs.unshift(job);
          } else {
            blocksPerOwner[job.owner].jobs.push(job);
          }
        }
      } else {
        if (curBlock && curBlock.owner == job.owner) {
          if (reverseGroup) {
            curBlock.jobs.unshift(job);
          } else {
            curBlock.jobs.push(job);
          }
        } else {
          curBlock = {
            owner: job.owner,
            owner_id: job.owner_id,
            jobs: [ job ]
          };
          if (reverseGroup) {
            blocks.unshift(curBlock);
          } else {
            blocks.push(curBlock);
          }
        }
      }
    }
    return blocks;
  }

  function sortJobGroups(jobGroups, maxLinesPerGroup, maxLinesPerCol) {
    // sort job names
    for (var i=0; i<jobGroups.length; i++) {
      jobGroups[i].jobs.sort(function(a,b) {
        if (a.job_name < b.job_name) return -1;
        else if (a.job_name > b.job_name) return 1;
        else return 0;
      });
    }

    // LPT sort
    // - sort by height, reverse
    jobGroups.sort(function(a,b) {
      if (a.jobs.length < b.jobs.length) return 1;
      else if (a.jobs.length > b.jobs.length) return -1;
      else return 0;
    });

    var numberOfBins = 1, newBinAdded = true;
    while (newBinAdded) {
      newBinAdded = false;
      var binHeights = [];
      for (var i=0; i<numberOfBins; i++) {
        binHeights.push(0);
      }
      for (var i=0; i<jobGroups.length; i++) {
        var b = 0, jobGroup = jobGroups[i],
            minBin = -1, minBinHeight = 100000,
            jobGroupHeight = Math.min(maxLinesPerGroup, jobGroup.jobs.length + 2);
        // find a column where this would fit
        // (there is always room in a new column)
        minBin = binHeights.length;
        for (var b=0; b<binHeights.length; b++) {
          if (binHeights[b] + jobGroupHeight <= maxLinesPerCol) {
            // this group would fit here,
            // but is it the emptiest so far?
            if (binHeights[b] < minBinHeight) {
              // yes, it might be the emptiest column
              minBin = b;
              minBinHeight = binHeights[b];
            }
          }
        }
        // add a new column?
        if (minBin >= binHeights.length) {
          numberOfBins++;
          newBinAdded = true;
          break;
        }
        // add jobGroup to column
        jobGroup.column = minBin;
        binHeights[minBin] += jobGroupHeight;
      }
    }

    // order by column
    jobGroups.sort(function(a,b) {
      if (a.column < b.column) return -1;
      else if (a.column > b.column) return 1;
      else return 0;
    });

    return jobGroups;
  }

  String.prototype.hashCode = function(){
    var hash = 0, i, char;
    if (this.length == 0) return hash;
    for (i = 0, l = this.length; i < l; i++) {
        char  = this.charCodeAt(i);
        hash  = ((hash<<5)-hash)+char;
        hash |= 0; // Convert to 32bit integer
    }
    return hash;
  };

  function randomHSLColor(name) {
    // var h = Math.random() * 360;
    var h = name.hashCode();
    h = Math.round(Math.random() * 60) * 6;
    return 'hsl(' + h + ',30%,45%)';
  }

  function userJobGroup(jobGroup, maxJobs) {
    var container = document.createElement('li'),
        strong = document.createElement('strong'),
        ul = document.createElement('ul'),
        span, li;

    container.user = { owner_id: jobGroup.owner_id };
    container.className = 'jobgroup owner-' + jobGroup.owner_id + ' jobgroup-' + jobGroup.owner.toLowerCase().replace(/[^a-z]+/,'');

    container.appendChild(strong);
    strong.appendChild(document.createTextNode(jobGroup.owner));

    if (jobGroup.jobs.length > 1) {
      span = document.createElement('span');
      span.className = 'multi';
      span.appendChild(document.createTextNode('\u00d7 ' + jobGroup.jobs.length));
      container.appendChild(span);
    }

    var n = jobGroup.jobs.length;
    if (maxJobs && maxJobs < n) {
      n = maxJobs;
    }
    var previousJobName = null;
    for (var i=0; n > 0 && i<jobGroup.jobs.length; i++) {
      if (previousJobName != jobGroup.jobs[i].job_name) {
        li = document.createElement('li');
        li.appendChild(document.createTextNode(jobGroup.jobs[i].job_name));
        ul.appendChild(li);
        previousJobName = jobGroup.jobs[i].job_name;
        n--;
      }
    }
    while (n > 0) {
      li = document.createElement('li');
      li.appendChild(document.createTextNode('\u00a0'));
      ul.appendChild(li);
      n--;
    }

    container.appendChild(ul);
    return container;
  }

  var QUEUES = [ 'hour', 'day', 'week', 'month' ],
      STATES = [ 'qw', 'r', 'z' ]; 

  function showStats(stats) {
    var allUsers = [],
        allUserIDs = {};

    for (var s=0; s<STATES.length; s++) {
      var state = STATES[s];
      var MAX_LINES_PER_GROUP = (state == 'r' ? 14 : 8);
      var MAX_LINES_PER_COL = 20;

      var container = document.createDocumentFragment();
      for (var q=0; q<QUEUES.length; q++) {
        var queue = QUEUES[q];
        var td = document.createElement('td'),
            div = document.createElement('div'),
            ul;

        var jobGroups = [];
        if (stats[queue] && stats[queue][state]) {
          jobGroups = summariseJobList(stats[queue][state],
                                       true, state == 'qw');
          collectUsers(stats[queue][state], allUsers, allUserIDs);
          if (state == 'r') {
            sortJobGroups(jobGroups, MAX_LINES_PER_GROUP, MAX_LINES_PER_COL);
          }
        }
            
        div.className = 'queue';

        if (state == 'r') {
          var h2 = document.createElement('h2');
          h2.appendChild(document.createTextNode(queue));
          div.appendChild(h2);
        } else if (state == 'z' && jobGroups.length > 0) {
          var arrow = document.createElement('div'),
              i = document.createElement('i');
          i.className = 'icon-circle-arrow-down';
          arrow.className = 'arrow';
          arrow.appendChild(i);
          div.appendChild(arrow);
        }

        ul = document.createElement('ul');
        ul.className = 'jobgroups';

        var curColLines = MAX_LINES_PER_COL,
            curCol = 0;

        for (var i=0; i<jobGroups.length; i++) {
          var groupHeight = 2 + Math.min(jobGroups[i].jobs.length, MAX_LINES_PER_GROUP - 2);
          curColLines -= groupHeight;
          if ((curColLines < 0 && state == 'r') || (jobGroups[i].column && curCol < jobGroups[i].column)) {
            div.appendChild(ul);
            ul = document.createElement('ul');
            ul.className = 'jobgroups';
            curColLines = MAX_LINES_PER_COL - groupHeight;
            curCol = jobGroups[i].column;
          }
          ul.appendChild(userJobGroup(jobGroups[i], MAX_LINES_PER_GROUP - 2));
        }

        div.appendChild(ul);

        if (state == 'qw' && jobGroups.length > 0) {
          var arrow = document.createElement('div'),
              i = document.createElement('i');
          i.className = 'icon-circle-arrow-down';
          arrow.className = 'arrow';
          arrow.appendChild(i);
          div.appendChild(arrow);
        }

        td.appendChild(div);
        container.appendChild(td);
      }

      var tr; 
      if (state == 'r') {
        tr = document.getElementById('running-jobs');
      } else if (state == 'qw') {
        tr = document.getElementById('queued-jobs');
      } else if (state == 'z') {
        tr = document.getElementById('finished-jobs');
      }
      $(tr).empty();
      tr.appendChild(container);
    }

    var userToggleCollect = document.createDocumentFragment();
    allUsers.sort();
    for (var i=0; i<allUsers.length; i++) {
      var user = allUserIDs[allUsers[i]];
      if (user) {
        var li = document.createElement('li'),
            span = document.createElement('span');
        span.className = 'owner-' + user.owner_id + ' toggle';
        li.className = 'toggle-' + user.owner_id;
        li.user = user;
        li.appendChild(span);
        li.appendChild(document.createTextNode(' ' + user.owner));
        userToggleCollect.appendChild(li);
      }
    }
    $('owner-toggle').empty().appendChild(userToggleCollect);
  }

  function updateStats() {
    var myJSONRemote = new Request.JSON({
      url: '/queue-stats.json',
      noCache: true,
      onSuccess: function(stats) {
        showStats(stats.stats);
        $('timestamp').innerHTML = stats.datetime;
        equalElements($$('table.queues .running-jobs .queue'));
      }
    }).get();
  }

  function toggleOwner(owner_id) {
    var enabled = (document.body.className.match(/only-owner-[0-9]+/) == 'only-owner-'+owner_id);
    document.body.className = document.body.className.replace(/\s*only-owner(-[0-9]+)?\s*/g, ' ')
                                                     .replace(/\s*all-owners\s*/g, ' ');
    if (enabled || owner_id == -1) { 
      document.body.className += 'all-owners';
    } else {
      document.body.className += 'only-owner only-owner-'+owner_id;
    }
  }

  function equalElements(els){
    // make elements equal height to max height of the set.
    var height = Math.max.apply(Math, els.map(function(el){
      return el.getSize().y;
    }));

    if (window.console && window.console.log) {
      console.log('Equalising queue heights to ' + height + 'px');
    }
    els.setStyle('height', height);
  };

  $('owner-toggle').addEvent('click', function(e) {
    var tgt = e.target;
    if (tgt.nodeName == 'SPAN') {
      tgt = tgt.parentNode;
    }
    if (tgt.user) {
      toggleOwner(tgt.user.owner_id);
    }
  });

  $$('table.queues').addEvent('click', function(e) {
    var tgt = $(e.target).getParent('li.jobgroup') || e.target;
    if (tgt && tgt.user) {
      toggleOwner(tgt.user.owner_id);
    } else {
      toggleOwner(-1);
    }
  });

  updateStats();
  window.setInterval(updateStats, 15000);

}());

