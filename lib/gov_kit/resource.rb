module GovKit
    
  # Parent class of resources returned by GovKit.
  #
  class Resource
    include HTTParty
    format :json

    attr_reader :attributes
    attr_reader :raw_response

    def initialize(attributes = {})
      @attributes = {}
      @raw_response = attributes

      unload(attributes)
    end

    # Returns a hash of the response object, potentially useful for comparison
    # on sync
    #
    def to_md5
      Digest::MD5.hexdigest(@raw_response.body)
    end

    # Handles the basic responses we might get back from Net::HTTP. 
    # On success, returns a new Resource based on the response.
    #
    # On failure, throws an error.
    #
    # If a service returns something other than a 404 when an object is not found,
    # you'll need to handle that in the subclass.
    #
    def self.parse(response)
      raise ResourceNotFound, "Resource not found" unless !response.blank?

      if response.class == HTTParty::Response
        case response.response
          when Net::HTTPNotFound
            raise ResourceNotFound, "404 Not Found"
          when Net::HTTPUnauthorized
            raise NotAuthorized, "401 Not Authorized; have you set up your API key?"
          when Net::HTTPServerError
            raise ServerError, '5xx server error'
          when Net::HTTPClientError
            raise ClientError, '4xx client error'
        end
      end
      
      instantiate(response)
    end

    # Instantiate new GovKit::Resources.
    #
    # +record+ is a hash of values returned by a service, 
    # or an array of hashes.
    #
    # If +record+ is a hash, return a single GovKit::Resource.
    # If it is an array, return an array of GovKit::Resources.
    #
    def self.instantiate(record)
      if record.is_a?(Array)
        instantiate_collection(record)
      else
        new(record)
      end
    end

    def self.instantiate_collection(collection)
      collection.collect! { |record| new(record) }
    end

    # Fills the @attributes hash with new resources generated from the 
    # members of the +attributes+ hash, 
    #
    def unload(attributes)
      raise ArgumentError, "expected an attributes Hash, got #{attributes.inspect}" unless attributes.is_a?(Hash)

      attributes.each do |key, value|
        @attributes[key.to_s] =
          case value
            when Array
              resource = resource_for_collection(key)
              value.map do |attrs|
                if attrs.is_a?(String) || attrs.is_a?(Numeric)
                  attrs.duplicable? ? attrs.dup : attrs
                else
                  resource.new(attrs)
                end
              end
            when Hash
              resource = find_or_create_resource_for(key)
              resource.new(value)
            else
              value.dup rescue value
          end
      end
      self
    end

    private

    # Finds a member of the GovKit module with the given name.
    # If the resource doesn't exist, creates it.
    #
    def resource_for_collection(name)
      find_or_create_resource_for(name.to_s.singularize)
    end

    # Searches each module in +ancestors+ for members named +resource_name+
    # Returns the named resource
    # Throws a NameError if none of the resources in the list contains +resource_name+
    #
    def find_resource_in_modules(resource_name, ancestors)
      if namespace = ancestors.detect { |a| a.constants.include?(resource_name.to_sym) }
        return namespace.const_get(resource_name)
      else
        raise NameError, "Namespace for #{namespace} not found"
      end
    end

    # Searches the GovKit module for a resource with the name +name+, cleaned and camelized
    # Returns that resource.
    # If the resource isn't found, it's created.
    #
    def find_or_create_resource_for(name)
      resource_name = name.to_s.gsub(/^[_\-+]/,'').gsub(/^(\-?\d)/, "n#{$1}").gsub(/(\s|-)/, '').camelize
      if self.class.parents.size > 1
        find_resource_in_modules(resource_name, self.class.parents)
      else
        self.class.const_get(resource_name)
      end
    rescue NameError
      if self.class.const_defined?(resource_name)
        resource = self.class.const_get(resource_name)
      else
        resource = self.class.const_set(resource_name, Class.new(GovKit::Resource))
      end
      resource
    end

    def method_missing(method_symbol, * arguments) #:nodoc:
      method_name = method_symbol.to_s

      case method_name.last
        when "="
          attributes[method_name.first(-1)] = arguments.first
        when "?"
          !attributes[method_name.first(-1)].blank?
        when "]"
          attributes[arguments.first.to_s]
        else
          attributes.has_key?(method_name) ? attributes[method_name] : super
      end
    end
  end
end
