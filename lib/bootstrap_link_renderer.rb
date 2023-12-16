# frozen_string_literal: true

module WillPaginate
  module Sinatra
    module Helpers
      include ViewHelpers

      def will_paginate(collection, options = {}) # :nodoc:
        options = options.merge(renderer: Bootstrap4LinkRenderer) unless options[:renderer]
        super(collection, options)
      end
    end

    class Bootstrap4LinkRenderer < WillPaginate::ViewHelpers::LinkRenderer
      protected

      def url(page)
        str = File.join(request.script_name.to_s, request.path_info)
        params = request.GET.merge(param_name.to_s => page.to_s)
        params.update @options[:params] if @options[:params]
        str << '?' << build_query(params)
      end

      def html_container(html)
        tag :nav, tag(:ul, html, class: 'pagination justify-content-center'), 'aria-label': 'Page navigation'
      end

      def page_number(page)
        if page == current_page
          tag :li, link(page, page, class: 'page-link'), class: 'page-item active'
        else
          tag :li, link(page, page, class: 'page-link'), class: 'page-item'
        end
      end

      def previous_or_next_page(page, text, _classname, _something)
        if page
          tag(:li, link(text, page, class: 'page-link'), { class: 'page-item' })
        else
          tag(:li, link(text, page, class: 'page-link'), { class: 'page-item disabled', tabindex: '-1' })
        end
      end

      def gap
        text = @template.will_paginate_translate(:page_gap) { '&hellip;' }
        %(<li class="page-item disabled" tabindex="-1"><a class="page-link" href="#">#{text}</a></span>)
      end

      def request
        @template.request
      end

      def build_query(params)
        Rack::Utils.build_nested_query params
      end
    end

    def self.registered(app)
      app.helpers Helpers
    end

    ::Sinatra.register self
  end
end
