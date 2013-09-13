(function(){

  var tableUpdateTimeout = null;
  function scheduleUpdateTableFilter() {
    if (tableUpdateTimeout) window.clearTimeout(tableUpdateTimeout);
    tableUpdateTimeout = window.setTimeout(updateTableFilter, 500);
  }
  function updateTableFilter() {
    if (tableUpdateTimeout) window.clearTimeout(tableUpdateTimeout);

    if (window.console && window.console.log) {
      window.console.log('Filtering table...');
    }
  
    var filterRow = $('table-filter-input-row');
    if (!filterRow) return;

    var td = filterRow.firstChild;
    var cols = 0;
    var filters = [];
    var filter_data = [];
    while (td) {
      if (td.nodeName=='TD') {
        var input = td.firstChild;
        if (input && input.nodeName=='INPUT') {
          if (input.value!='') {
            filters[cols] = input.value.toLowerCase();
            filter_data.push(input.name+'='+encodeURIComponent(input.value));
          }
        }
        cols++;
      }
      td = td.nextSibling;
    }

    if (window.history && window.history.replaceState) {
      window.history.replaceState({}, '', '?'+filter_data.join('&'));
    }

    var form = $('table-filter');
    form.style.display = 'none';

    var tr = $$('#table-filter tbody')[0].firstChild;
    while (tr) {
      if (tr.nodeName=='TR') {
        var matching = true;
        if (tr.cachedFields) {
          for (var i=0; i<cols; i++) {
            if (filters[i] && !tr.cachedFields[i].contains(filters[i])) {
              matching = false; break;
            }
          }
        } else {
          var td = tr.firstChild;
          var col = 0;
          var t;
          var cachedFields = [];
          while (td) {
            if (td.nodeName=='TD') {
              t = td;
              if (t && t.firstChild) t = t.firstChild;
              if (t && t.nodeName == 'A') t = t.firstChild;
              t = (t && t.nodeValue) ? t.nodeValue : '';
              t = t.toLowerCase();
              cachedFields.push(t);
              if (filters[col] && !t.contains(filters[col])) {
                matching = false;
              }
              col++;
            }
            td = td.nextSibling;
          }
          tr.cachedFields = cachedFields;
        }
        tr.style.display = (matching ? '' : 'none');
      }
      tr = tr.nextSibling;
    }

    form.style.display = '';
  }

  function appendCurrentFilterToLink(e) {
    var targ;
    if (!e) var e = window.event;
    if (e.target) targ = e.target;
    else if (e.srcElement) targ = e.srcElement;
    if (targ.className == 'date-nav-link') {
      targ.href = targ.href.replace(/\?.+$/, '') + window.location.search;
    }
  }

  window.addEvent('domready', function() {
    $('table-filter').onsubmit = function() { updateTableFilter(); return false; };
    $$('#table-filter input.filter').addEvent('keyup',  scheduleUpdateTableFilter);
    $$('#table-filter input.filter').addEvent('click',  scheduleUpdateTableFilter);
    $$('#table-filter input.filter').addEvent('change', scheduleUpdateTableFilter);
    $('date-nav-links').addEvent('click', appendCurrentFilterToLink);
    updateTableFilter();

    window.setTimeout(function() { window.location.href = window.location.href; }, 60000);
  });

})();

