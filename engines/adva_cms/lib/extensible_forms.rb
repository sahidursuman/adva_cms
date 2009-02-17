require 'action_view/helpers/form_helper'

module ActionView
  module Helpers
    module FormHelper
      def fields_for_with_resource_form_builders(name, *args, &block)
        name = singular_class_name(name) unless name.class.in?(String, Symbol)

        options = args.last.is_a?(Hash) ? args.last : {}
        options[:builder] ||= pick_form_builder(name)

        fields_for_without_resource_form_builders(name, *args, &block)
      end
      alias_method_chain :fields_for, :resource_form_builders
      
      def field_set(object_name, name, content = nil, options = {}, &block)
        InstanceTag.new(object_name, name, self, options.delete(:object)).to_field_set_tag(content, options, &block)
      end
      
      protected
        def singular_class_name(name)
          ActionController::RecordIdentifier.singular_class_name(name)
        end
        
        def pick_form_builder(name)
          "#{name.to_s.classify}FormBuilder".constantize
        rescue NameError
          ActionView::Base.default_form_builder
        end
    end
  
    class InstanceTag
      def to_field_set_tag(content = nil, options = {}, &block)
        options = options.stringify_keys
        name_and_id = options.dup
        add_default_name_and_id(name_and_id)
        options.delete("index")
        options["id"] ||= name_and_id["id"]
        content ||= @template_object.capture(&block) if block_given?
        content_tag("fieldset", content, options)
      end
    end
  end
end

class ExtensibleFormBuilder < ActionView::Helpers::FormBuilder
  class_inheritable_accessor :callbacks
  self.callbacks = { :before => {}, :after => {} }

  class_inheritable_accessor :options
  self.options = { :labels => false }
  
  class << self
    def before(object_name, method, string = nil, &block)
      add_callback(:before, object_name, method, string || block)
    end
  
    def after(object_name, method, string = nil, &block)
      add_callback(:after, object_name, method, string || block)
    end

    protected
    
      def add_callback(stage, object_name, method, callback)
        method = method.to_sym
        callbacks[stage][object_name] ||= { }
        callbacks[stage][object_name][method] ||= []
        callbacks[stage][object_name][method] << callback
      end
  end
  
  helpers = field_helpers + %w(date_select datetime_select time_select) -
                            %w(hidden_field label fields_for apply_form_for_options!)

  helpers.each do |method_name|
    define_method(method_name) do |*args, &block| # use the block to define options
      options = args.extract_options!
      name  = args.first

      with_callbacks(name) do
        tag = super(*(args << options), &block)
        tag = labelize(tag, name, options) if self.options[:labels]
        tag
      end
    end
  end
  
  def field_set(*args, &block)
    options = args.extract_options!
    name    = args.first
    name ||= :default_fields
    @template.concat with_callbacks(name) {
      legend = options.delete(:legend) || ''
      legend = @template.content_tag('legend', legend) unless legend.blank?
      @template.field_set(@object_name, name, nil, objectify_options(options)) do
        legend + (block ? block.call : '')
      end
    }
  end
  
  protected
  
    def labelize(tag, method, options = {})
      @template.content_tag(:p, label(method, options[:label]) + tag)
    end

    def with_callbacks(method, &block)
      result = ''
      result += run_callbacks(:before, method) if method
      result += yield
      result += run_callbacks(:after, method) if method
      result
    end

    def run_callbacks(stage, method)
      if callbacks = callbacks_for(stage, method.to_sym)
        callbacks.inject('') do |result, callback|
          result + case callback
            when Proc; callback.call(self) # instance_eval(&callback)
            else       callback
          end
        end
      end || ''
    end
    
    def callbacks_for(stage, method)
      object_name = @object_name.try(:to_sym)
      self.callbacks[stage][object_name] and 
      self.callbacks[stage][object_name][method.to_sym]
    end

    # yep, we gotta do this crap because there doesn't seem to be a sane way
    # to hook into actionview's form_helper methods
    def extract_id(tag)
      tag =~ /id="([^"]+)"/
      $1
    end
end

ActionView::Base.default_form_builder = ExtensibleFormBuilder