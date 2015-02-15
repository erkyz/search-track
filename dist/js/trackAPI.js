
/*
 *
 * API used for parsing the information stored in chrome.storage for searches
 *
 */

/*
 * Structure of our storage
 * queries: { 
 *     name: _Name / query term used
 *     date: _last time the query was performed
 *  }
 * tab
 */
var generateUUID;

generateUUID = function() {
  var d, uuid;
  d = (new Date).getTime();
  uuid = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
    var r;
    r = (d + Math.random() * 16) % 16 | 0;
    d = Math.floor(d / 16);
    return (c === 'x' ? r : r & 0x3 | 0x8).toString(16);
  });
  return uuid;
};

window.SearchInfo = (function() {
  var obj, settings, updateFunction, updateID;
  obj = {};
  obj.db = TAFFY();
  updateID = generateUUID();
  updateFunction = null;
  settings = {
    template: {},
    onDBChange: function() {
      return chrome.storage.local.set({
        'queries': {
          db: this,
          updateId: updateID
        }
      });
    }
  };
  chrome.storage.onChanged.addListener(function(changes, areaName) {
    if (changes.queries != null) {
      if (changes.queries.newValue == null) {
        obj.db = TAFFY();
        obj.db.settings(settings);
        if (updateFunction != null) {
          return updateFunction();
        }
      } else if (changes.queries.newValue.updateid !== updateID) {
        obj.db = TAFFY(changes.queries.newValue.db, false);
        obj.db.settings(settings);
        if (updateFunction != null) {
          return updateFunction();
        }
      }
    }
  });
  chrome.storage.local.get('queries', function(retVal) {
    if (retVal.queries != null) {
      obj.db = TAFFY(retVal.queries.db);
    }
    obj.db.settings(settings);
    if (updateFunction != null) {
      return updateFunction();
    }
  });
  obj.clearDB = function() {
    chrome.storage.local.remove('queries');
    return obj.db = TAFFY();
  };
  obj.db.settings(settings);
  obj.updateFunction = function(fn) {
    return updateFunction = fn;
  };
  return obj;
})();

window.PageInfo = (function() {
  var obj, settings, updateFunction, updateID;
  obj = {};
  obj.db = TAFFY();
  updateID = generateUUID();
  updateFunction = null;
  settings = {
    template: {},
    onDBChange: function() {
      return chrome.storage.local.set({
        'pages': {
          db: this,
          updateId: updateID
        }
      });
    },
    onUpdate: function(before, changes) {
      var htmls, searchInfo, tabs;
      if ((this.html != null) && (this.keywords == null)) {
        searchInfo = SearchInfo.db({
          tabs: {
            has: this.tab
          }
        });
        if (!searchInfo.first()) {
          alert('no search Info:' + this.tab + this.query);
          return;
        }
        tabs = searchInfo.first().tabs;
        tabs = _.map(tabs, function(tabId) {
          return PageInfo.db({
            tab: tabId
          }).first();
        });
        tabs = _.filter(tabs, function(tab) {
          return tab.html != null;
        });
        tabs.push(this);
        htmls = _.map(tabs, function(tab) {
          return tab.html;
        });
        return $.ajax({
          type: 'POST',
          url: 'http://127.0.0.1:5000/searchInfo',
          data: {
            'data': JSON.stringify({
              'htmls': htmls
            })
          }
        }).success(function(results) {
          results = JSON.parse(results);
          results = results['tfidfs'];
          return _.map(_.zip(tabs, results), function(tab_result) {
            var result, tab, _tab;
            tab = tab_result[0];
            result = tab_result[1];
            _tab = PageInfo.db({
              tab: tab.tab
            });
            return _tab.update({
              keywords: result
            });
          });
        });
      }
    }
  };
  chrome.storage.onChanged.addListener(function(changes, areaName) {
    if (changes.pages != null) {
      if (changes.pages.newValue == null) {
        obj.db = TAFFY();
        obj.db.settings(settings);
        if (updateFunction != null) {
          return updateFunction();
        }
      } else if (changes.pages.newValue.updateid !== updateID) {
        obj.db = TAFFY(changes.pages.newValue.db, false);
        obj.db.settings(settings);
        if (updateFunction != null) {
          return updateFunction();
        }
      }
    }
  });
  chrome.storage.local.get('pages', function(retVal) {
    if (retVal.pages != null) {
      obj.db = TAFFY(retVal.pages.db);
    }
    obj.db.settings(settings);
    if (updateFunction != null) {
      return updateFunction();
    }
  });
  obj.clearDB = function() {
    chrome.storage.local.remove('pages');
    return obj.db = TAFFY();
  };
  obj.db.settings(settings);
  obj.updateFunction = function(fn) {
    return updateFunction = fn;
  };
  return obj;
})();

//# sourceMappingURL=trackAPI.js.map
