import '../src/shared/data_row'
import '../src/traits/data_viz'

(function() {

  function showNotification() {
    UIkit.notification($(this).data('submitNotification'), {
      status: 'primary',
      pos: 'top-center',
      offset: '100px'
    });
  }

  function fetchForm(option) {
    var data = $('#new_term_query').serializeArray();

    $('.js-term-form-dimmer').addClass('active');

    if (option) {
      data.push(option)
    }

    $.ajax({
      method: 'POST',
      data: $.param(data),
      url: 'search_form',
      success: function(res) {
        $('#term_form_container').html(res)
        setupForm();
        $('.js-term-form-dimmer').removeClass('active');
      }
    });
  }

  function buildTypeahead(selector, typeaheadOptions, dataOptions, datumField, selectFn) {
    const $elmt = $(selector)
        , $contain = $elmt.closest('.js-typeahead-wrap')
        , $clearField = $contain.find('.js-clear-field')
        ;

    $elmt.typeahead(typeaheadOptions, dataOptions).bind('typeahead:selected', function(evt, datum, name) {
      var $target = $(evt.target);

      $target.data('lastCleanVal', $target.val());
      $(evt.target).closest('.js-typeahead-wrap').find('.js-typeahead-field').val(datum[datumField]);

      if (selectFn) {
        selectFn();
      }
    });

    $elmt.on('input', function() {
      const $this = $(this)
          ;

      if ($this.val().length === 0) {
        $this.data('lastCleanVal', '');
        $contain.find('.js-typeahead-field').val('');

        if (selectFn) {
          selectFn();
        }
        $clearField.addClass('uk-hidden');
      } else {
        $clearField.removeClass('uk-hidden');
      }
    });

    $elmt.on('blur', function() {
      var lastCleanVal = $(this).data('lastCleanVal');

      if (typeof lastCleanVal !== 'undefined') {
        $(this).val($(this).data('lastCleanVal'));
      }
    });

    $clearField.click(() => {
      $elmt.val('')
      $elmt.trigger('input');
    });
  }

  function setupMetaFilters() {
    $('.js-show-meta-filters').click(function() {
      fetchForm({
        name: 'show_extra_fields',
        value: $(this).data('index')
      });
    })

    $('.js-hide-meta-filters').click(function() {
      fetchForm({
        name: 'hide_extra_fields',
        value: $(this).data('index')
      });
    });

    $('.js-meta-object-typeahead').each(function() {
      buildTypeahead(this, { minLength: 0 }, {
        name: 'meta-obj-names',
        display: 'name',
        limit: Infinity,
        source: new Bloodhound({
          datumTokenizer: Bloodhound.tokenizers.obj.whitespace('name'),
          queryTokenizer: Bloodhound.tokenizers.whitespace,
          remote: {
            url: '/' +
              (document.documentElement.lang === I18n.defaultLocale ? '' : document.documentElement.lang + '/') +
              '/terms/meta_object_terms.json?' + new URLSearchParams({
              query: 'QUERY', meta_predicate: $(this).data('metaPredicate')
            }).toString(),
            wildcard: 'QUERY'
          }
        })
      }, 'id', fetchForm)
    });

  }

  function setupForm() {
    $('.js-search-type input[type=radio]').change(fetchForm);

    $('.js-term-select').each(function() {
      if ($(this).find('option').length <= 1) {
        $(this).attr('disabled', true);
      } else {
        $(this).attr('disabled', false);
      }
    });

    buildTypeahead('.js-clade-typeahead', {}, {
      name: 'clade-filter-names',
      display: 'name',
      limit: Infinity,
      source: EOL.searchNamesNoMultipleText
    }, 'id', fetchForm);

    var predSource = new Bloodhound({
      datumTokenizer: Bloodhound.tokenizers.obj.whitespace('name'),
      queryTokenizer: Bloodhound.tokenizers.whitespace,
      remote: {
        url: '/' +
          (document.documentElement.lang === I18n.defaultLocale ? '' : document.documentElement.lang + '/') +
          'terms/trait_search_predicates.json?' + new URLSearchParams({
          query: 'QUERY'
        }).toString(),
        wildcard: 'QUERY'
      }
    });

    buildTypeahead('.js-predicate-typeahead', { minLength: 0 }, {
      name: 'pred-names',
      display: 'name',
      limit: Infinity,
      source: predSource
    }, 'id', fetchForm);

    $('.js-object-term-for-predicate-typeahead').each(function() {
      var source = new Bloodhound({
        datumTokenizer: Bloodhound.tokenizers.obj.whitespace('name'),
        queryTokenizer: Bloodhound.tokenizers.whitespace,
        remote: {
          url: '/' +
            (document.documentElement.lang === I18n.defaultLocale ? '' : document.documentElement.lang + '/') +
            'terms/object_terms_for_predicate.json?' + new URLSearchParams({
            query: 'QUERY',
            predicate_id: $(this).data('predicateId')
          }).toString(),
          wildcard: 'QUERY'
        }
      });
      source.initialize();

      buildTypeahead(this, { minLength: 0 }, {
        display: 'name',
        source: source,
        minLength: 0,
        limit: Infinity
      }, 'id', null)
    });


    buildTypeahead('.js-object-term-typeahead', {}, {
      name: 'obj-names',
      display: 'name',
      limit: Infinity,
      source: EOL.searchObjectTerms
    }, 'id', fetchForm);

    buildTypeahead('.js-resource-typeahead', { minLength: 0 }, {
      name: 'resource',
      display: 'name',
      limit: Infinity,
      source: EOL.searchResources
    }, 'id', fetchForm);

    $('.js-add-filter').click(function(e) {
      e.preventDefault();
      fetchForm({
        name: 'add_filter',
        value: true
      });
    });

    $('.js-remove-filter').click(function(e) {
      fetchForm({
        name: 'remove_filter',
        value: $(this).data('index')
      });
    });

    $('#new_term_query').submit(showNotification);

    setupMetaFilters();
    setupTermSelects();
  }

  function setupTermSelects() {
    setupTermSelect($('.js-term-select'));
  }

  function setupTermSelect($select) {
    $select.change(function(e) {
      var $that = $(this)
        , $filterGroup = $that.closest('.js-filter-row-group')
        ;

      if ($that.val()) {
        setValFromTermSelect($filterGroup, $that);
      } else {
        // $.prev only matches the immediate previous sibling, which doesn't work here. This technically fetches a collection, but it'll only have length 1
        var $prev = $that.closest('.js-term-select-children').prevAll('.js-term-select');

        if ($prev.val()) {
          setValFromTermSelect($filterGroup, $prev);
        } else {
          setTermVal($filterGroup, $filterGroup.find('.js-top-term-id').val());
        }
      }

      fetchForm();
    });
  }

  function setValFromTermSelect($filterGroup, $select) {
    setTermVal($filterGroup, $select.val());
  }

  function setTermVal($filterGroup, id) {
    $filterGroup.find('.js-term-id').val(id);
  }

  function loadPieChart() {
    var minWidth = 750
      , $contain = $('.js-pie-contain')
      , loaded = false
      ;

    if ($contain.length) {
      pieChartHelper();
      $(window).resize(pieChartHelper);
    }

    // CSS media queries don't work here because the pie chart d3 code needs it to be visible when loaded
    function pieChartHelper() {
      var width = $(window).width();

      if (!loaded && width >= minWidth) {
        loaded = true;
        loadViz($contain, TraitDataViz.buildPieChart);
      } else if (loaded) {
        if (width < minWidth) {
          $contain.hide();
        } else {
          $contain.show()
        }
      }
    }
  }

  $(function() {
    $('.show-raw-query').click(function() {
      $('.js-raw-query').removeClass('is-hidden');
      $(this).remove();
    });
    setupForm();
  });
})();
