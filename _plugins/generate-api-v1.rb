# This script creates API files for version 1 of the endoflife.date API.
#
# There are multiples endpoints :
#
# - /api/v1/ - list all major endpoints (those not requiring a parameter)
# - /api/v1/products/ - list all products
# - /api/v1/products/<product>/ - get a single product details
# - /api/v1/products/<product>/latest - get details on the latest cycle for the given product
# - /api/v1/products/<product>/<cycle> - get details on the given cycle for the given product
# - /api/v1/categories/ - list categories used on endoflife.date
# - /api/v1/categories/<category> - list products having the given category
# - /api/v1/tags/ - list tags used on endoflife.date
# - /api/v1/tags/<tag> - list products having the given tag


require 'jekyll'

module ApiV1

  VERSION = '1.0.0'
  MAJOR_VERSION = VERSION.split('.')[0]

  STRIP_HTML_BLOCKS = Regexp.union(
    /<script.*?<\/script>/m,
    /<!--.*?-->/m,
    /<style.*?<\/style>/m
  )
  STRIP_HTML_TAGS = /<.*?>/m

  # Remove HTML from a string (such as an LTS label).
  # This is the equivalent of Liquid::StandardFilters.strip_html, which cannot be used
  # unfortunately.
  def self.strip_html(input)
    empty = ''.freeze
    result = input.to_s.gsub(STRIP_HTML_BLOCKS, empty)
    result.gsub!(STRIP_HTML_TAGS, empty)
    result
  end

  def self.site_url(site, path)
    "#{site.config['url']}#{path}"
  end

  def self.api_url(site, path)
    site_url(site, "/api/v#{ApiV1::MAJOR_VERSION}#{path}")
  end

  class ApiGenerator < Jekyll::Generator
    safe true
    priority :lowest

    TOPIC = "API " + ApiV1::VERSION + ":"

    def generate(site)
      @site = site
      Jekyll.logger.info TOPIC, "Generating..."

      add_index_page(site)
      product_pages = add_product_pages(site)
      add_all_products_page(site, product_pages)

      add_all_categories_page(site, product_pages)
      add_category_pages(site, product_pages)
      add_all_tags_page(site, product_pages)
      add_tag_pages(site, product_pages)

      Jekyll.logger.info TOPIC, "Generation done."
    end

    private

    def add_index_page(site)
      site.pages << JsonPage.new(site, '/', [
        { name: "products", uri: "#{ApiV1.api_url(site, '/products/')}" },
        { name: "categories", uri: "#{ApiV1.api_url(site, '/categories/')}" },
        { name: "tags", uri: "#{ApiV1.api_url(site, '/tags/')}" },
      ])
    end

    def add_product_pages(site)
      product_pages = []

      site.pages.each do |page|
        if page.data['layout'] == 'product'
          product_pages << page
          add_product_page(site, page)
        end
      end

      return product_pages
    end

    def add_product_page(site, page)
      site.pages << ProductJsonPage.new(site, page)

      site.pages << ProductCycleJsonPage.new(site, page, page.data['releases'][0], 'latest')
      page.data['releases'].each do |cycle|
        site.pages << ProductCycleJsonPage.new(site, page, cycle)
      end
    end

    def add_all_products_page(site, products)
      site.pages << ProductsJsonPage.new(site, '/products/', products)
    end

    def add_category_pages(site, products)
      pages_by_category = {}

      products.each do |product|
        category = product.data['category'] || 'unknown'
        add_to_map(pages_by_category, category, product)
      end

      pages_by_category.each do |category, products|
        site.pages << ProductsJsonPage.new(site, "/categories/#{category}", products)
      end
    end

    def add_all_categories_page(site, products)
      categories = products.map { |product| product.data['category'] }.uniq.sort

      data = categories.map { |category| {
        name: category,
        uri: "#{ApiV1.api_url(site, "/categories/#{category}/")}"
      }}
      meta = { total: categories.size() }

      site.pages << JsonPage.new(site, '/categories/', data, meta)
    end

    def add_tag_pages(site, products)
      products_by_tag = {}

      products.each do |product|
        product.data['tags'].each { |tag| add_to_map(products_by_tag, tag, product) }
      end

      products_by_tag.each do |tag, products|
        site.pages << ProductsJsonPage.new(site, "/tags/#{tag}", products)
      end
    end

    def add_all_tags_page(site, products)
      tags = products.flat_map { |product| product.data['tags'] }.uniq.sort

      data = tags.map { |tag| {
        name: tag,
        uri: "#{ApiV1.api_url(site, "/tags/#{tag}/")}"
      }}
      meta = { total: tags.size() }

      site.pages << JsonPage.new(site, '/tags/', data, meta)
    end

    def add_to_map(map, key, page)
      if map.has_key? key
        map[key] << page
      else
        map[key] = [page]
      end
    end
  end

  class JsonPage < Jekyll::Page
    def initialize(site, path, data, metadata = {})
      @site = site
      @base = site.source
      @dir = "api/v#{ApiV1::MAJOR_VERSION}#{path}"
      @name = "index.json"
      @data = {}
      @data['layout'] = 'json'
      @data['data'] = metadata
      @data['data']['result'] = data
      @data['data']['schema_version'] = ApiV1::VERSION

      self.process(@name)
    end

    protected

    def links_to_json(site, product)
      {
        icon: product.data['iconUrl'],
        html: ApiV1.site_url(site, "/#{product.data['id']}"),
        releasePolicy: product.data['releasePolicyLink'],
      }
    end

    def cycle_to_json(cycle)
      {
        name: cycle['releaseCycle'],
        codename: cycle['codename'],
        label: ApiV1.strip_html(cycle['label']),
        date: cycle['releaseDate'],
        support: cycle['support'],
        lts: cycle['lts'],
        eol: cycle['eol'],
        discontinued: cycle['discontinued'],
        extendedSupport: cycle['extendedSupport'],
        latest: {
          name: cycle['latest'],
          date: cycle['latestReleaseDate'],
          link: cycle['link'],
        }
      }
    end

    def product_summary_to_json(site, product)
      {
        name: product.data['id'],
        label: product.data['title'],
        category: product.data['category'],
        tags: product.data['tags'],
        identifiers: product.data['identifiers'].map { |identifier| {
          type: identifier.keys.first,
          id: identifier.values.first
        } },
        uri: ApiV1.api_url(site, "/products/#{product.data['id']}/")
      }
    end

    def product_to_json(site, product)
      product_summary_to_json(site, product)
        .except(:uri)
        .merge({
                 links: links_to_json(site, product),
                 versionCommand: product.data['versionCommand'],
                 cycles: product.data['releases'].map { |cycle| cycle_to_json(cycle) }
               })
    end
  end

  class ProductsJsonPage < JsonPage
    def initialize(site, path, products)
      data = products.map { |product| product_summary_to_json(site, product) }
      meta = { total: products.size() }
      super(site, path, data, meta)
    end
  end

  class ProductJsonPage < JsonPage
    def initialize(site, product)
      path = "/products/#{product.data['id']}"
      data = product_to_json(site, product)
      meta = {
        # https://github.com/gjtorikian/jekyll-last-modified-at/blob/master/lib/jekyll-last-modified-at/determinator.rb
        last_modified: product.data['last_modified_at'].last_modified_at_time.iso8601,
        auto: product.data.has_key?('auto'),
      }
      super(site, path, data, meta)
    end
  end

  class ProductCycleJsonPage < JsonPage
    def initialize(site, product, cycle, identifier = nil)
      name = identifier ? identifier : cycle['id']
      path = "/products/#{product.data['id']}/cycles/#{name}"
      data = cycle_to_json(cycle)
      super(site, path, data)
    end
  end
end
