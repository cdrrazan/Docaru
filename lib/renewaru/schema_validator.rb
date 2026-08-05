# frozen_string_literal: true

require "json"

module Renewaru
  # A small JSON Schema (2020-12) validator covering the subset the RenewalRule
  # schema actually uses.
  #
  # Written by hand rather than pulled from a gem for one reason: a contributor
  # editing a YAML file should be able to check their work with nothing but the
  # Ruby that ships with their machine. A dataset that requires a toolchain to
  # contribute to gets fewer contributions, and external contributions are the
  # thing this repository is trying to prove it can attract.
  #
  # The JSON Schema file remains canonical. Any consumer that wants full
  # validation can point a real library at it; this class is the zero-install
  # path, and it is deliberately strict — unknown keywords are ignored, but every
  # keyword it does implement is enforced.
  class SchemaValidator
    Error = Struct.new(:path, :message) do
      def to_s = "#{path.empty? ? "(root)" : path}: #{message}"
    end

    def initialize(schema)
      @root = schema
    end

    def self.from_file(path)
      new(JSON.parse(File.read(path)))
    end

    # Returns an array of Error. Empty means valid.
    def validate(data)
      @errors = []
      check(data, @root, "")
      @errors
    end

    private

    def add(path, message)
      @errors << Error.new(path, message)
    end

    def resolve(schema)
      return schema unless schema.is_a?(Hash) && schema.key?("$ref")

      ref = schema["$ref"]
      unless ref.start_with?("#/")
        add("", "unsupported external $ref #{ref}")
        return {}
      end

      target = ref.delete_prefix("#/").split("/").reduce(@root) do |node, segment|
        node.is_a?(Hash) ? node[segment] : nil
      end

      unless target
        add("", "unresolvable $ref #{ref}")
        return {}
      end

      # A $ref sibling may carry an overriding description; the target wins on
      # everything else.
      resolve(target)
    end

    def check(data, schema, path)
      schema = resolve(schema)
      return if schema.empty?

      check_type(data, schema, path)
      check_enum(data, schema, path)
      check_string(data, schema, path)
      check_number(data, schema, path)
      check_array(data, schema, path)
      check_object(data, schema, path)
      check_composition(data, schema, path)
    end

    TYPES = {
      "object" => ->(v) { v.is_a?(Hash) },
      "array" => ->(v) { v.is_a?(Array) },
      "string" => ->(v) { v.is_a?(String) },
      "integer" => ->(v) { v.is_a?(Integer) || (v.is_a?(Float) && v == v.to_i) },
      "number" => ->(v) { v.is_a?(Numeric) && !v.is_a?(TrueClass) },
      "boolean" => ->(v) { v == true || v == false },
      "null" => ->(v) { v.nil? }
    }.freeze

    def check_type(data, schema, path)
      expected = schema["type"]
      return unless expected

      allowed = Array(expected)
      return if allowed.any? { |t| TYPES.fetch(t, ->(_) { true }).call(data) }

      add(path, "expected #{allowed.join(" or ")}, got #{describe(data)}")
    end

    def check_enum(data, schema, path)
      if schema.key?("const") && data != schema["const"]
        add(path, "must be #{schema["const"].inspect}, got #{data.inspect}")
      end

      return unless (values = schema["enum"])
      return if values.include?(data)

      add(path, "#{data.inspect} is not one of: #{values.join(", ")}")
    end

    def check_string(data, schema, path)
      return unless data.is_a?(String)

      if (min = schema["minLength"]) && data.length < min
        add(path, "must be at least #{min} characters (got #{data.length})")
      end
      if (max = schema["maxLength"]) && data.length > max
        add(path, "must be at most #{max} characters (got #{data.length})")
      end
      return unless (pattern = schema["pattern"])
      return if Regexp.new(pattern).match?(data)

      add(path, "#{data.inspect} does not match #{pattern}")
    end

    def check_number(data, schema, path)
      return unless data.is_a?(Numeric) && !data.is_a?(TrueClass)

      if (min = schema["minimum"]) && data < min
        add(path, "must be >= #{min} (got #{data})")
      end
      if (max = schema["maximum"]) && data > max
        add(path, "must be <= #{max} (got #{data})")
      end
      if (min = schema["exclusiveMinimum"]) && data <= min
        add(path, "must be > #{min} (got #{data})")
      end
      return unless (max = schema["exclusiveMaximum"]) && data >= max

      add(path, "must be < #{max} (got #{data})")
    end

    def check_array(data, schema, path)
      return unless data.is_a?(Array)

      if (min = schema["minItems"]) && data.length < min
        add(path, "must have at least #{min} item(s) (got #{data.length})")
      end
      if (max = schema["maxItems"]) && data.length > max
        add(path, "must have at most #{max} item(s) (got #{data.length})")
      end
      return unless (items = schema["items"])

      data.each_with_index { |item, i| check(item, items, "#{path}/#{i}") }
    end

    def check_object(data, schema, path)
      return unless data.is_a?(Hash)

      Array(schema["required"]).each do |key|
        add(path, "missing required property #{key.inspect}") unless data.key?(key)
      end

      if (min = schema["minProperties"]) && data.size < min
        add(path, "must have at least #{min} propert#{min == 1 ? "y" : "ies"} (got #{data.size})")
      end

      properties = schema["properties"] || {}
      data.each do |key, value|
        child = "#{path}/#{key}"

        if (names = schema["propertyNames"])
          check(key, names, "#{path} (property name #{key.inspect})")
        end

        if properties.key?(key)
          check(value, properties[key], child)
          next
        end

        case schema["additionalProperties"]
        when false
          add(path, "unknown property #{key.inspect}")
        when Hash
          check(value, schema["additionalProperties"], child)
        end
      end
    end

    def check_composition(data, schema, path)
      Array(schema["allOf"]).each { |sub| check_conditional(data, sub, path) }
      check_conditional(data, schema, path)
    end

    # if/then, used by the schema to demand provenance on verified rules.
    def check_conditional(data, schema, path)
      return unless schema.is_a?(Hash)

      if schema.key?("if")
        check(data, schema["then"], path) if matches?(data, schema["if"]) && schema["then"]
        check(data, schema["else"], path) if !matches?(data, schema["if"]) && schema["else"]
      end

      return unless schema.key?("required") || schema.key?("properties")
      return if schema.equal?(@root) || schema.key?("if")

      # allOf branches carrying plain constraints.
      check_object(data, schema, path)
    end

    def matches?(data, schema)
      probe = SchemaValidator.new(@root)
      probe.validate_subschema(data, schema).empty?
    end

    protected

    def validate_subschema(data, schema)
      @errors = []
      check(data, schema, "")
      @errors
    end

    private

    def describe(value)
      case value
      when nil then "null"
      when true, false then "boolean"
      when Integer then "integer"
      when Float then "number"
      when String then "string"
      when Array then "array"
      when Hash then "object"
      else value.class.name.downcase
      end
    end
  end
end
