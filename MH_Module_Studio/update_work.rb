# encoding: UTF-8
require 'digest'
require_relative 'parametric'
require_relative 'scale_plan'
require_relative 'dc_options'

module MH
  module ModuleStudio
    # Native adapters stop at calculation barriers. A trial operation is aborted
    # before returning to the event loop; only portable JSON enters the worker.
    # The final replay uses prepared calculations and commits once, atomically.
    module UpdateWork
      extend self
      MAX_BYTES=32*1024*1024
      attr_reader :last_metrics
      class Deferred < Exception # rubocop:disable Lint/InheritException -- Control flow must bypass ordinary geometry-error/Undo handlers.
        attr_reader :key,:kind,:source
        def initialize(key,kind,source)
          super('Calculation deferred');@key=key;@kind=kind;@source=source
        end
      end
      class Prepared < Exception;end # rubocop:disable Lint/InheritException -- Same transaction-unwind protocol as Deferred.
      class Cancelled < StandardError;end

      def context
        Thread.current[:mh_module_update]
      end

      def active?
        !context.nil?
      end

      def probing?
        context && context[:probe]
      end

      def calculate(kind,*args)
        job=context
        return dispatch(kind,args) unless job
        # Hash large rules in memory; worker input is encoded only on a miss.
        raw=args.first
        if kind==:rule && raw.is_a?(Hash)
          canonical=RuleSystem::KIND==raw['kind'] ? JSON.generate(raw) : job[:canonical_rules]&.fetch(raw,nil)
        end
        canonical=nil if job[:canonical].equal?(raw)
        digest=job[:raw].equal?(raw) && !canonical ? job[:raw_digest] : Digest::SHA256.hexdigest(Marshal.dump(canonical ? ['rule',canonical] : args))
        key=Digest::SHA256.hexdigest(kind.to_s+digest)
        stored=job[:cache][key]
        raise Core::Error,'Dữ liệu dựng đã thay đổi. Đọc lại module rồi thử lại.' if !stored && !job[:probe]
        unless stored
          input=canonical ? ['rule',canonical] : JSON.generate(args)
          raise Deferred.new(key,kind,[input,args])
        end
        payload=JSON.parse(stored)
        raise Core::Error,payload['error'] if payload.key?('error')
        if kind==:rule && !payload.key?('result')
          job[:canonical_rules][payload]=stored unless raw.is_a?(String)
          return payload
        end
        result=payload.fetch('result')
        if kind==:rule
          job[:canonical_rules][result]=stored unless raw.is_a?(String)
          return result
        end
        job[:results][key] ||= Core.copy_data(result)
        Core.copy_data(job[:results][key])
      end

      def rule(raw)
        calculate(:rule,raw)
      end

      # Validation proves canonical rule identity for this job. A changed hash
      # takes the ordinary full-rule path instead of sharing the encoding.
      def canonical_rule(rule)
        return unless context && rule.is_a?(Hash)
        encoded=context[:canonical_rules][rule]
        return unless encoded && Core.rule!(JSON.parse(encoded))==rule
        encoded
      end

      def seed_json(metadata)
        seed=%w[rule_json parameter_values_json formula_envelope_json].to_h { |key| [key,metadata[key]] }.compact
        JSON.generate(seed)
      end

      def snapshot(data)
        data.reject { |key,_| %w[id label source captured_at].include?(key) }
      end

      # Explicit whitelist: never evaluate imported Ruby or call any host API.
      def dispatch(kind,args)
        case kind
        when :rule then Core.rule!(args.fetch(0).is_a?(String) ? JSON.parse(args[0]) : args[0])
        when :scale then ScalePlan.plan(*args,validated:true)
        when :plan then Core.plan(*args)
        when :stamp
          metadata=Parametric.stamp_metadata(*args)
          metadata['seed_json']=UpdateWork.seed_json(metadata)
          metadata
        when :options_edit
          rule,requested=args;rows=Parametric.variables(rule)
          requested.each { |id,input| DCOptions.assign!(rule,rows,id,input) }
          edited=Parametric.edit_variables(rule,rows)
          [edited,Parametric.targets(edited)]
        else raise Core::Error,'Unsupported update calculation.'
        end
      end

      def commit(model)
        raise Prepared if probing?
        model.commit_operation
      end

      def pending?(model)
        @jobs&.key?(model) || false
      end

      def valid_context?(entities)
        job=context
        !job || Array(entities).all? do |entity|
          entity.respond_to?(:valid?) && entity.valid? && entity.respond_to?(:model) && entity.model.equal?(job[:model])
        end
      end

      def cancel(model)
        job=@jobs&.delete(model)
        job[:cancelled]=true if job
        job
      end

      def submit(model,key:,guard: nil,complete: nil,&action)
        watch(model)
        previous=cancel(model)
        job={model:model,key:key,action:action,guard:guard,complete:complete,
             revision:@watchers.fetch(model).revision,cache:{},results:{},canonical_rules:{},seeds:{},probe:true,bytes:0,steps:0,max_step_ms:0,
             started:Process.clock_gettime(Process::CLOCK_MONOTONIC)}
        @jobs ||= {};@jobs[model]=job
        previous[:complete]&.call(:superseded,nil) if previous
        schedule(job)
        job
      end

      def schedule(job)
        UI.start_timer(0.01,false) { advance(job) }
      end

      def valid?(job)
        model=job[:model]
        !job[:cancelled] && @jobs[model].equal?(job) && Sketchup.active_model.equal?(model) &&
          (!model.respond_to?(:valid?) || model.valid?) && @watchers.fetch(model).revision==job[:revision] &&
          (!job[:guard] || job[:guard].call)
      end

      def advance(job)
        started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return unless @jobs&.fetch(job[:model],nil).equal?(job)
        return finish(job,:cancelled,nil) unless valid?(job)
        return schedule(job) if @watchers.fetch(job[:model]).open?
        if job[:worker]
          return schedule(job) if job[:worker].alive?
          if job[:result]
            key,value=job[:result]
            if value.nil?
              return finish(job,:cancelled,nil) unless valid?(job)
            elsif value==false
              return finish(job,:error,Core::Error.new(job[:prefetch_error]))
            else
              job[:bytes]+=value.bytesize
              raise Core::Error,'Lượt cập nhật vượt giới hạn bộ nhớ.' if job[:bytes]>MAX_BYTES
              job[:cache][key]=value unless key==:prepared
            end
            job.delete(:worker)
          end
            job.delete(:result);job.delete(:worker);job.delete(:queued)
        end
        job[:steps]+=1
        Thread.current[:mh_module_update]=job
        job[:action].call
        finish(job,:done,nil)
      rescue Deferred=>request
        # Every adapter has already aborted its trial transaction here.
        job[:probe]=true
        queued=job[:queued] ||= {}
        queued[request.kind] ||= request
        unless job[:worker]&.alive?
          job[:worker]=Thread.new { compute(job,queued.values) }
        end
        schedule(job)
      rescue Prepared
        job[:probe]=false
        return schedule(job) if job[:worker]&.alive?
        return finish(job,:cancelled,nil) unless valid?(job)
        job.delete(:queued)
        schedule(job)
      rescue StandardError=>error
        finish(job,:error,error)
      ensure
        job[:max_step_ms]=[job[:max_step_ms] || 0,(Process.clock_gettime(Process::CLOCK_MONOTONIC)-started)*1000].max if started
        Thread.current[:mh_module_update]=nil
      end

      def compute(job,requests)
        request=Array(requests).first
        raise Cancelled if job[:cancelled]
        Thread.current.priority=-2
        deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+0.003
        events=0
        trace=TracePoint.new(:call,:b_call) do
          events+=1
          next unless (events%64).zero?
          raise Cancelled if job[:cancelled]
          next unless Process.clock_gettime(Process::CLOCK_MONOTONIC)>=deadline
          sleep(0.001) # rubocop:disable SketchupSuggestions/Sleep -- Worker only: release the GVL; the UI never sleeps or joins this thread.
          deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+0.003
        end
        value=trace.enable(target_thread:Thread.current) do
          source,_original=request.source
          input=source.is_a?(String) ? JSON.parse(source) : [Core.rule!(JSON.parse(source.last))]
          error=nil
          result=begin
            dispatch(request.kind,input)
          rescue StandardError=>caught
            error=caught
            nil
          end
          value=if request.kind==:rule
            error ? JSON.generate('error'=>error.message) : JSON.generate(result)
          else
            JSON.generate(error ? {'error'=>error.message} : {'result'=>result})
          end
          job[:result]=[request.key,value]
          nil
        end
      rescue Cancelled
        nil
      rescue StandardError=>error
        job[:result]=[request.key,JSON.generate('error'=>error.message)] if request && !job[:cancelled]
      ensure
        trace&.disable
      end

      def finish(job,status,error)
        return unless @jobs&.fetch(job[:model],nil).equal?(job)
        metrics=job.slice(:key,:steps,:max_step_ms,:bytes)
        @jobs.delete(job[:model]);job[:cancelled]=true
        @last_metrics=metrics.merge(status:status,calculations:job[:cache].length,
          elapsed_ms:(Process.clock_gettime(Process::CLOCK_MONOTONIC)-job[:started])*1000)
        Thread.current[:mh_module_update]=nil
        job[:complete]&.call(status,error)
      end

      def watch(model)
        @watchers ||= {}
        @watchers[model] ||= begin
          observer=Observer.new;model.add_observer(observer);observer
        end
      end

      if defined?(Sketchup::ModelObserver)
        class Observer < Sketchup::ModelObserver
          attr_reader :revision
          def initialize
            super();@revision=0;@open=false
          end
          def open?
            @open
          end
          def onTransactionStart(_model)
            return if UpdateWork.active?
            @open=true
          end
          def onTransactionEmpty(_model)
            @open=false unless UpdateWork.active?
          end
          %i[onTransactionCommit onTransactionAbort onTransactionUndo onTransactionRedo onActivePathChanged].each do |event|
            define_method(event) do |_model|
              next if UpdateWork.active?
              @open=false;@revision+=1
            end
          end
        end
      end
    end
  end
end
