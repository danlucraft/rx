
class Rx
  def initialize(opt={})
    @registry = { }

    if opt[:load_core] then
      @registry[''] = {
        'all'  => Rx::Type::Core::All,
        'any'  => Rx::Type::Core::Any,
        'arr'  => Rx::Type::Core::Arr,
        'bool' => Rx::Type::Core::Bool,
        'def'  => Rx::Type::Core::Def,
        'fail' => Rx::Type::Core::Fail,
        'int'  => Rx::Type::Core::Int,
        'map'  => Rx::Type::Core::Map,
        'nil'  => Rx::Type::Core::Nil,
        'num'  => Rx::Type::Core::Num,
        'one'  => Rx::Type::Core::One,
        'rec'  => Rx::Type::Core::Rec,
        'seq'  => Rx::Type::Core::Seq,
        'str'  => Rx::Type::Core::Str,
      }
    end
  end

  def parse_name(schema_name)
    match = schema_name.match(/\A\/([-._a-z0-9]*)\/([-._a-z0-9]+)\z/)
    raise Rx::Exception.new('invalid schema name') unless match
    return { :authority => match[1], :subname => match[2] }
  end

  def make_schema(schema)
    schema = { 'type' => schema } if schema.instance_of?(String)

    if not (schema.instance_of?(Hash) and schema['type']) then
      raise Rx::Exception.new('invalid type')
    end

    sn = parse_name(schema['type'])

    authority = @registry[ sn[:authority] ]
    raise Rx::Exception.new('unknown authority') unless authority

    type_class = authority[ sn[:subname] ]
    raise Rx::Exception.new('unknown subname') unless type_class

    return type_class.new(schema, self)
  end
end

class Rx::Helper; end;
class Rx::Helper::Range
  def initialize(arg)
    @range = { }

    arg.each_pair { |key,value|
      if not ['min', 'max', 'min-ex', 'max-ex'].index(key) then
        raise Rx::Exception.new("illegal argument for Rx::Helper::Range")
      end

      @range[ key ] = value
    }
  end

  def check(value)
    return false if ! @range['min'   ].nil? and value <  @range['min'   ]
    return false if ! @range['min-ex'].nil? and value <= @range['min-ex']
    return false if ! @range['max-ex'].nil? and value >= @range['max-ex']
    return false if ! @range['max'   ].nil? and value >  @range['max'   ]
    return true
  end
end

class Rx::Type
  def initialize
    raise Rx::Exception.new("Rx::Type subclass didn't implement initialization")
  end

  def authority
    raise Rx::Exception.new("Rx::Type subclass didn't provide authority")
  end

  def subname
    raise Rx::Exception.new("Rx::Type subclass didn't provide subname")
  end

  def name
    return sprintf('/%s/%s', authority, subname)
  end

  def assert_valid_params(param)
    param.each_key { |k|
      unless self.allowed_param?(k) then
        raise Rx::Exception.new("unknown parameter #{k} for #{self.name}")
      end
    }
  end

  module NoParams
    def initialize(param, rx)
      return if param.keys.length == 0
      return if param.keys == [ 'type' ]

      raise Rx::Exception.new('this type is not parameterized')
    end
  end
end

class Rx::Exception < Exception
end

class Rx::Type::Core < Rx::Type
  def authority; ''; end

  class All < Rx::Type::Core
    @@allowed_param = { 'of' => true, 'type' => true }
    def allowed_param?(p); return @@allowed_param[p]; end

    def initialize(param, rx)
      assert_valid_params(param)

      if ! param.has_key?('of') then
        raise Rx::Exception.new("no 'of' parameter provided for //all")
      end

      if param['of'].length == 0 then
        raise Rx::Exception.new("no schemata provided for 'of' in //all")
      end

      @alts = [ ]
      param['of'].each { |alt| @alts.push(rx.make_schema(alt)) }
    end

    def subname; return 'all'; end

    def check(value)
      @alts.each { |alt| return false if ! alt.check(value) }
      return true
    end
  end

  class Any < Rx::Type::Core
    @@allowed_param = { 'of' => true, 'type' => true }
    def allowed_param?(p); return @@allowed_param[p]; end

    def initialize(param, rx)
      assert_valid_params(param)

      if param['of'] then
        if param['of'].length == 0 then
          raise Rx::Exception.new("no alternatives provided for 'of' in //any")
        end

        @alts = [ ]
        param['of'].each { |alt| @alts.push(rx.make_schema(alt)) }
      end
    end

    def subname; return 'any'; end

    def check(value)
      return true unless @alts

      @alts.each { |alt| return true if alt.check(value) }

      return false
    end
  end

  class Arr < Rx::Type::Core
    @@allowed_param = { 'contents' => true, 'length' => true, 'type' => true }
    def allowed_param?(p); return @@allowed_param[p]; end

    def initialize(param, rx)
      assert_valid_params(param)

      unless param['contents'] then
        raise Rx::Exception.new('no contents schema given for //arr')
      end

      @contents_schema = rx.make_schema( param['contents'] )

      if param['length'] then
        @length_range = Rx::Helper::Range.new( param['length'] )
      end
    end

    def check(value)
      return false unless value.instance_of?(Array)

      if @length_range
        return false unless @length_range.check(value.length)
      end

      if @contents_schema then
        value.each { |v| return false unless @contents_schema.check(v) }
      end

      return true
    end
  end

  class Bool < Rx::Type::Core
    include Rx::Type::NoParams

    def check(value)
      return true if value.instance_of?(TrueClass)
      return true if value.instance_of?(FalseClass)
      return false
    end
  end

  class Fail < Rx::Type::Core
    include Rx::Type::NoParams
    def check(value); return false; end
  end

  class Def < Rx::Type::Core
    include Rx::Type::NoParams
    def check(value); return ! value.nil?; end
  end

  class Map < Rx::Type::Core
    @@allowed_param = { 'values' => true, 'type' => true }
    def allowed_param?(p); return @@allowed_param[p]; end

    def initialize(param, rx)
      assert_valid_params(param)

      if param['values'] then
        @value_schema = rx.make_schema(param['values'])
      end
    end

    def check(value)
      return false unless value.instance_of?(Hash)

      if @value_schema
        value.each_value { |v| return false unless @value_schema.check(v) }
      end

      return true
    end
  end

  class Nil < Rx::Type::Core
    include Rx::Type::NoParams
    def check(value); return value.nil?; end
  end

  class Num < Rx::Type::Core
    def subname; return 'num'; end;
    @@allowed_param = { 'range' => true, 'type' => true, 'value' => true }
    def allowed_param?(p); return @@allowed_param[p]; end

    def initialize(param, rx)
      assert_valid_params(param)

      if param.has_key?('value') then
        if ! param['value'].kind_of?(Numeric) then
          raise Rx::Exception.new("invalid value parameter for //num")
        end

        @value = param['value']
      end

      if param['range'] then
        @value_range = Rx::Helper::Range.new( param['range'] )
      end
    end

    def check(value)
      if not value.kind_of?(Numeric) then; return false; end;
      return false if @value_range and not @value_range.check(value)
      return false if @value and value != @value
      return true
    end
  end

  class Int < Rx::Type::Core::Num
    def subname; return 'int'; end

    def initialize(param, rx)
      super

      if param.has_key?('value') then
        if ! param['value'].kind_of?(Numeric) or param['value'] % 1 != 0 then
          raise Rx::Exception.new("invalid value parameter for //int")
        end

        @value = param['value']
      end

      if param['range'] then
        @value_range = Rx::Helper::Range.new( param['range'] )
      end
    end

    def check(value)
      return false unless super;
      return false unless value % 1 == 0
      return true
    end
  end

  class One < Rx::Type::Core
    include Rx::Type::NoParams

    def check(value)
      [ Numeric, String, TrueClass, FalseClass ].each { |cls|
        return true if value.kind_of?(cls)
      }

      return false
    end
  end

  class Rec < Rx::Type::Core
    @@allowed_param = {
      'type' => true,
      'rest' => true,
      'required' => true,
      'optional' => true,
    }

    def allowed_param?(p); return @@allowed_param[p]; end

    def initialize(param, rx)
      assert_valid_params(param)

      @field = { }

      @rest_schema = rx.make_schema(param['rest']) if param['rest']

      [ 'optional', 'required' ].each { |type|
        next unless param[type]
        param[type].keys.each { |field|
          if @field[field] then
            raise Rx::Exception.new("#{field} in both required and optional")
          end

          @field[field] = {
            :required => (type == 'required'),
            :schema   => rx.make_schema(param[type][field]),
          }
        }
      }
    end

    def check(value)
      return false unless value.instance_of?(Hash)

      rest = [ ]

      value.each_pair { |field, field_value|
        unless @field[field] then
          rest.push(field)
          next
        end

        return false unless @field[field][:schema].check(field_value)
      }

      @field.select { |k,v| @field[k][:required] }.each { |pair|
        return false unless value.has_key?(pair[0])
      }

      if rest.length > 0 then
        return unless @rest_schema
        rest_hash = { }
        rest.each { |field| rest_hash[field] = value[field] }
        return false unless @rest_schema.check(rest_hash)
      end

      return true
    end
  end

  class Seq < Rx::Type::Core
    @@allowed_param = { 'tail' => true, 'contents' => true, 'type' => true }
    def allowed_param?(p); return @@allowed_param[p]; end

    def initialize(param, rx)
      assert_valid_params(param)

      unless param['contents'] and param['contents'].kind_of?(Array) then
        raise Rx::Exception.new('missing or invalid contents for //seq')
      end

      @content_schemata = param['contents'].map { |s| rx.make_schema(s) }

      if param['tail'] then
        @tail_schema = rx.make_schema(param['tail'])
      end
    end

    def check(value)
      return false unless value.instance_of?(Array)
      return false if value.length < @content_schemata.length

      @content_schemata.each_index { |i|
        return false unless @content_schemata[i].check(value[i])
      }

      if value.length > @content_schemata.length then
        return false unless @tail_schema and @tail_schema.check(value[
          @content_schemata.length,
          value.length - @content_schemata.length
        ])
      end

      return true
    end
  end

  class Str < Rx::Type::Core
    @@allowed_param = { 'type' => true, 'value' => true }
    def allowed_param?(p); return @@allowed_param[p]; end

    def initialize(param, rx)
      assert_valid_params(param)

      if param.has_key?('value') then
        if ! param['value'].instance_of?(String) then
          raise Rx::Exception.new("invalid value parameter for //str")
        end

        @value = param['value']
      end
    end

    def check(value)
      return false unless value.instance_of?(String)
      return false if @value and value != @value
      return true
    end
  end
end

