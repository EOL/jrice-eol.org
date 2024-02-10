import routes from './routes.js.erb'

if (!window.EOL) {
  window.EOL = {};


  var eolReadyCbs = [];
  EOL.onReady = function(cb) {
    eolReadyCbs.push(cb);
  }

  EOL.parseHashParams = function() {
    var hash = window.location.hash,
      keyValPairs = null,
      params = {};

    if (hash) {
      hash = hash.replace('#', '');
      keyValPairs = hash.split('&');

      $.each(keyValPairs, function(i, pair) {
        var keyAndVal = pair.split('=');
        params[keyAndVal[0]] = keyAndVal[1]
      });
    }

    return params;
  }

  EOL.enable_search_pagination = function() {
    $("#search_results .uk-pagination a")
      .unbind("click")
      .on("click", function() {
        $(this).closest(".search_result_container").dimmer("show");
      });
  };

  EOL.enable_tab_nav = function() {
    $("#page_nav a,#small_page_nav a").on("click", function() {
        $("#tab_content").dimmer("show");
      }).unbind("ajax:complete")
      .bind("ajax:complete", function() {
        $("#tab_content").dimmer("hide");
        $("#page_nav li").removeClass("uk-active");
        $("#small_page_nav > a").removeClass("active");
        $(this).addClass("active").parent().addClass("uk-active");
        if ($("#page_nav > li:first-of-type").hasClass("uk-active")) {
          $("#name-header").attr("hidden", "hidden");
        } else {
          $("#name-header").removeAttr("hidden");
        }
        history.pushState(null, "", this.href);
      }).unbind("ajax:error")
      .bind("ajax:error", function(evt, data, status) {
        if (status === "parsererror") {
        } else {
          UIkit.modal.alert('Sorry, there was an error loading this subtab.');
        }
      });
    EOL.dim_tab_on_pagination();
  };

  EOL.enable_spinners = function() {
    $(".actions.loaders button").on("click", function(e) {
      $(this).parent().dimmer("show");
    })
  };

  EOL.dim_tab_on_pagination = function() {
    $("#tab_content").dimmer("hide");
    $(".uk-pagination a").on("click", function(e) {
      $("#tab_content").dimmer("show");
    });
  };

  EOL.meta_data_toggle = function() {
    $(".meta_data_toggle").on("click", function(event) {
      var $parent = $(this).parent();
      var $div = $parent.find(".meta_data");
      if ($div.is(':visible')) {
        $div.hide();
      } else {
        if ($div.html() === "") {
          $.ajax({
            type: "GET",
            url: $(this).data("action"),
            // While they serve no purpose NOW... I am keeping these here for
            // future use.
            beforeSend: function() {
            },
            complete: function() {
              var offset = $parent.offset();
              if (offset) {
                $('html, body').animate({
                  scrollTop: offset.top - 100
                }, 'fast');
                return false;
              }
            },
            success: function(resp) {
            },
            error: function(xhr, textStatus, error) {
            }
          });
        } else {
          $div.show();
        }
      }
      return event.stopPropagation();
    });
    $(".meta_data").hide();
    EOL.enable_tab_nav();
  };

  EOL.enable_media_navigation = function() {
    $("#page_nav_content .dropdown").dropdown();
    /*
    $(".js-slide-modal a.uk-slidenav-large").on("click", function(e) {
      var link = $(this);
      thisId = link.data("this-id");
      tgtId = link.data("tgt-id");
      console.log("Switching images. This: " + thisId + " Target: " + tgtId);
      // Odd: removing this (extra show()) causes a RELOADED page of image
      // modals to stop working:
      UIkit.modal("#" + thisId).show();
      UIkit.modal("#" + thisId).hide();
      UIkit.modal("#" + tgtId).show();
    });
    */
    EOL.enable_tab_nav();
  };

  EOL.enable_data_toc = function() {
    $("#section_links a").on("click", function(e) {
      var link = $(this);
      $("#section_links .item.active").removeClass("active");
      link.parent().addClass("active");
      var secId = link.data("section-id");
      if (secId == "all") {
        $("table#data thead tr").show();
        $("table#data tbody tr").show();
        $("#data_type_glossary").show();
        $("#data_value_glossary").show();
      } else if (secId == "other") {
        $("table#data thead tr").show();
        $("table#data tbody tr").hide();
        $("table#data tbody tr.section_other").show();
        $("#data_type_glossary").hide();
        $("#data_value_glossary").hide();
      } else if (secId == "type_glossary") {
        $("table#data thead tr").hide();
        $("table#data tbody tr").hide();
        $("#data_type_glossary").show();
        $("#data_value_glossary").hide();
      } else if (secId == "value_glossary") {
        $("table#data thead tr").hide();
        $("table#data tbody tr").hide();
        $("#data_type_glossary").hide();
        $("#data_value_glossary").show();
      } else {
        $("table#data thead tr").show();
        $("table#data tbody tr").hide();
        $("table#data tbody tr.section_" + secId).show();
        $("#data_glossary").hide();
      }
      e.stopPropagation();
      e.preventDefault();
    });
  };

  EOL.teardown = function() {
    $(".typeahead").typeahead("destroy");
  };

  // Enable all semantic UI dropdowns
  EOL.enableDropdowns = function() {
    $('.ui.dropdown').dropdown();
  }

  EOL.ready = function() {
    var $flashes = $('.eol-flash');
    if ($flashes.length) {
      $flashes.each(function() {
        UIkit.notification($(this).data("text"), {
          status: 'primary',
          pos: 'top-center',
          offset: '100px'
        });
      });
    }

    if ($(".actions.loaders").length >= 1) {
      EOL.enable_spinners();
    }

    if ($("#topics").length === 1) {
      $.ajax({
        url: "/pages/topics.js",
        cache: false
      });
    }

    /*
     * NOTE: this enables the page 'comment' button. Disabled since there's an outstanding issue with discourse.
    if ($(".page_topics").length >= 1) {
      console.log("Fetching page comments...");
      $.ajax({
        url: "/pages/" + $($(".page_topics")[0]).data("id") + "/comments.js",
        cache: false
      });
    }
    */

    $(".disable-on-click").on("click", function() {
      $(this).closest(".button").addClass("disabled loading");
    });

    if ($("#gallery").length === 1) {
      EOL.enable_media_navigation();
    } else if ($("#page_data").length === 1) {
      EOL.enable_data_toc();
      EOL.meta_data_toggle();
    } else if ($("#data_table").length === 1) {
      EOL.meta_data_toggle();
    } else if ($("#search_results").length === 1) {
      EOL.enable_search_pagination();
    } else {
      EOL.enable_tab_nav();
    }
    // No "else" because it also has a gallery, so you can need both!
    /*
    if ($("#gmap").length >= 1) {
      EoLMap.init();
    }
    */
    $(window).bind("popstate", function() {
      // TODO: I'm not sure this is ever used. Check and remove, if not.
      $.getScript(location.href);
    });

    EOL.searchNamesNoMultipleText = new Bloodhound({
      datumTokenizer: Bloodhound.tokenizers.obj.whitespace('name'),
      queryTokenizer: Bloodhound.tokenizers.whitespace,
      remote: {
        url: '/' +
          (document.documentElement.lang === I18n.defaultLocale ? '' : document.documentElement.lang + '/') +
          'pages/autocomplete?' + new URLSearchParams({
          query: 'QUERY',
          no_multiple_text: true
        }).toString(),
        wildcard: 'QUERY'
      }
    });
    EOL.searchNamesNoMultipleText.initialize();

    // And this...
    EOL.searchUsers = new Bloodhound({
      datumTokenizer: Bloodhound.tokenizers.obj.whitespace('value'),
      queryTokenizer: Bloodhound.tokenizers.whitespace,
      // TODO: someday we should have a pre-populated list of common search terms
      // and load that here. prefetch: '../data/films/post_1960.json',
      remote: {
        url: '/' +
          (document.documentElement.lang === I18n.defaultLocale ? '' : document.documentElement.lang + '/') +
          'users/autocomplete?' + new URLSearchParams({
          query: 'QUERY'
        }).toString(),
        wildcard: 'QUERY'
      }
    });
    EOL.searchUsers.initialize();

    // Aaaaand this...
    EOL.searchPredicates = new Bloodhound({
      datumTokenizer: Bloodhound.tokenizers.obj.whitespace('name'),
      queryTokenizer: Bloodhound.tokenizers.nonword,
      remote: {
        url: '/' +
          (document.documentElement.lang === I18n.defaultLocale ? '' : document.documentElement.lang + '/') +
          'terms/predicate_glossary.json?' + new URLSearchParams({
          query: 'QUERY'
        }).toString(),
        wildcard: 'QUERY'
      }
    });
    EOL.searchPredicates.initialize();

    // And this!
    EOL.searchObjectTerms = new Bloodhound({
      datumTokenizer: Bloodhound.tokenizers.obj.whitespace('name'),
      queryTokenizer: Bloodhound.tokenizers.whitespace,
      remote: {
        url: '/' +
          (document.documentElement.lang === I18n.defaultLocale ? '' : document.documentElement.lang + '/') +
          'terms/object_term_glossary.json?' + new URLSearchParams({
          query: 'QUERY'
        }).toString(),
        wildcard: 'QUERY'
      }
    });
    EOL.searchObjectTerms.initialize();

    EOL.searchResources = new Bloodhound({
      datumTokenizer: Bloodhound.tokenizers.obj.whitespace('name'),
      queryTokenizer: Bloodhound.tokenizers.whitespace,
      remote: {
        url: '/' +
          (document.documentElement.lang === I18n.defaultLocale ? '' : document.documentElement.lang + '/') +
          'resources/autocomplete?' + new URLSearchParams({
          query: 'QUERY'
        }).toString(),
        wildcard: 'QUERY'
      }
    });
    EOL.searchResources.initialize();

    EOL.combinedAutocomplete = new Bloodhound({
      datumTokenizer: Bloodhound.tokenizers.obj.whitespace('name'),
      queryTokenizer: Bloodhound.tokenizers.whitespace,
      remote: {
        url: '/' +
          (document.documentElement.lang === I18n.defaultLocale ? '' : document.documentElement.lang + '/') +
          'autocomplete/QUERY',
        wildcard: 'QUERY'
      }
    });
    EOL.combinedAutocomplete.initialize();

    // Show/hide overlay
    EOL.showOverlay = function(id) {
      EOL.hideOverlay();
      var $overlay = $('#' + id);
      $overlay.removeClass('is-hidden');
      $('body').addClass('is-noscroll');
    }

    EOL.hideOverlay = function() {
      var $overlay = $('.js-overlay');
      $overlay.addClass('is-hidden');
      $('body').removeClass('is-noscroll');
    }


    /*
    if ($('.clade_filter .typeahead').length >= 1) {
      console.log("Enable clade filter typeahead.");
      $('.clade_filter .typeahead').typeahead(null, {
        name: 'clade-filter-names',
        display: 'name',
        source: EOL.searchNames
      }).bind('typeahead:selected', function(evt, datum, name) {
        console.log('typeahead:selected:', evt, datum, name);
        $(".clade_filter form input#clade").val(datum.id);
        $(".clade_filter form").submit();
      });
    };
    */

    if ($('.find_users .typeahead').length >= 1) {
      $('.find_users .typeahead').typeahead(null, {
        name: 'find-usernames',
        display: 'username',
        source: EOL.searchUsers
      }).bind('typeahead:selected', function(evt, datum, name) {
        $("form.find_users_form input#user_id").val(datum.id)
        $("form.find_users_form").submit();
      });
    };

    if ($('.predicate_filter .typeahead').length >= 1) {
      $('.predicate_filter .typeahead').typeahead(null, {
        name: 'find-predicates',
        display: 'predicates',
        source: EOL.searchPredicates,
        display: "name",
      }).bind('typeahead:selected', function(evt, datum, name) {
        $(".predicate_filter form input#and_predicate").val(datum.uri);
        $(".predicate_filter form").submit();
      });
    };

    if ($('.object_filter .typeahead').length >= 1) {
      $('.object_filter .typeahead').typeahead(null, {
        name: 'find-object-terms',
        display: 'object-terms',
        source: EOL.searchObjectTerms,
        display: "name",
      }).bind('typeahead:selected', function(evt, datum, name) {
        $(".object_filter form input#and_object").val(datum.uri);
        $(".object_filter form").submit();
      });
    };

    // Clean up duplicate search icons, argh:
    if ($(".uk-search-icon > svg:nth-of-type(2)").length >= 1) {
      $(".uk-search-icon > svg:nth-of-type(2)");
    };

    $('.js-overlay-x').click(EOL.hideOverlay);

    $('.js-bread-type-toggle').change(function() {
      $(this).submit();
    });

    var $navSearch = $('.js-nav-search')
      , navSearchResultsLimit = 7
      ;

    $navSearch.typeahead({
      minLength: 3,
      highlight: true
    }, {
      source: EOL.combinedAutocomplete,
      display: 'name',
      limit: navSearchResultsLimit,
      templates: {
        suggestion: function(item) {
          return `<div><a href="${item.url}">${item.name}</a></div>`
        },
        notFound: $navSearch.data('noResultsText')
      }
    })
    .bind('typeahead:select', function(e, item) {
      window.location = item.url;
    })
    .keypress(function(e) {
      if (e.which === 13) { // enter
        $(this).closest('form').submit();
      }
    });

    EOL.enableDropdowns();

    $.each(eolReadyCbs, function(i, cb) {
      cb();
    });
  };
}

$(EOL.ready);
