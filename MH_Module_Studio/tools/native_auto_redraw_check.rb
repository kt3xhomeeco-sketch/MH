# encoding: UTF-8
# Developer QA (coordinator-only): proves the superseded auto-redraw retry on
# real SketchUp geometry. Run in the pinned, empty, Untitled, idle session:
#
#   MH::ModuleStudio::NativeAutoRedrawCheck.start(mode: 'supersede', isolated: true)
#   MH::ModuleStudio::NativeAutoRedrawCheck.report      # repeat; never sleeps
#   MH::ModuleStudio::NativeAutoRedrawCheck.cleanup
#
# `mode: 'undo'` queues Scale on root B, issues native Undo immediately, then
# checks that B returns to its source thickness and the cancelled job does not
# reapply. `mode: 'supersede'` edits root A to T1=18.6 while B's Scale job is
# queued, then checks A=18.6 and B=17.6 after the deferred redraw.
# The global user library is never scanned or mutated: a private Library is
# built around the single exact asset row. No camera/selection/preference change.
module MH
  module ModuleStudio
    module NativeAutoRedrawCheck
      extend self

      ROOT='D:/Cong viec/Sketchup/DC/Modul_studio'
      ASSET_REL='Canh/Canh phai.skp'
      ENTRY_ID='qa-canh-phai'
      SOURCE_THICKNESS=17.6
      EDITED_THICKNESS=18.6
      SCALE_RATIO=1.8
      MM=25.4
      TOLERANCE=0.25
      POLL_DELAY=0.15
      B_OFFSET=80.0 # inches, keeps the QA roots far apart
      # Original commit timer plus the observer's forced redraw share this delay;
      # the duplicate-timer guard in redraw coalesces them.
      SETTLE_DELAY=0.3

      def start(mode: 'supersede', isolated: false)
        raise 'Chỉ chạy trên phiên QA cách ly.' unless isolated
        model=Sketchup.active_model
        refuse!('Không có SketchUp model.') unless model
        refuse!('Chỉ chạy trên Untitled trống.') unless model.path.to_s.empty?
        refuse!('Model QA phải trống trước khi bắt đầu.') unless model.entities.to_a.empty?
        refuse!('Không được đang chỉnh sửa trong context.') if model.active_path
        refuse!('Đang có cập nhật đang chờ.') if UpdateWork.pending?(model)
        refuse!('Đang có Scale đang chờ.') if ScaleRedraw.pending?(model)
        raise 'Chế độ QA không hợp lệ.' unless %w[supersede undo].include?(mode)
        Runtime.ensure_top_level(model)
        path=asset_path
        refuse!("Thiếu asset #{path}.") unless File.file?(path)
        @model=model
        @state={'mode'=>mode,'phase'=>'building','roots'=>[],'asset'=>path,
          'prerequisites'=>{'path'=>model.path.to_s,'entities'=>model.entities.to_a.length,
            'definitions'=>model.definitions.to_a.length,'active_path'=>!model.active_path.nil?}}
        @definitions_before=model.definitions.to_a.map(&:persistent_id)
        @materials_before=model.materials.to_a.map(&:name)
        @camera=camera_state(model)
        @selection=model.selection.to_a.map(&:entityID)
        @library=private_library(path)
        data=@library.preview(ENTRY_ID)
        operation=false
        begin
          model.start_operation('MH QA Auto Redraw',true)
          operation=true
          @roots=[
            @library.build_instance(data,Geom::Transformation.new),
            @library.build_instance(data,Geom::Transformation.new(Geom::Point3d.new(B_OFFSET,0,0)))
          ]
          model.commit_operation
          operation=false
        rescue StandardError=>error
          model.abort_operation if operation
          @state['phase']='error'
          @state['error']=error.message
          raise
        end
        @state['roots']=@roots.map { |root| root.persistent_id.to_s }
        @state['phase']='applying'
        UI.start_timer(SETTLE_DELAY,false) { MH::ModuleStudio::NativeAutoRedrawCheck.phase_apply }
        report
      end

      def phase_apply
        return unless @state && @state['phase']=='applying'
        return unless Sketchup.active_model.equal?(@model)
        a,b=@roots
        return fail_phase('Module QA đã bị xoá.') unless a&.valid? && b&.valid?
        observer=ScaleRedraw.instance_variable_get(:@observers)&.fetch(@model,nil)
        return fail_phase('Thiếu ScaleModelObserver.') unless observer
        @state['before']={'a'=>thickness(a),'b'=>thickness(b)}
        @state['geometry_before']=root_frames
        @model.start_operation('MH QA Scale B',true)
        # Compose the scale with the current transform so B's offset survives.
        b.transformation=b.transformation*Geom::Transformation.scaling(1,SCALE_RATIO,1)
        @model.commit_operation
        @state['after_scale']={'b'=>thickness(b)}
        @state['geometry_after_scale']=root_frames
        observer.redraw([b],observer.instance_variable_get(:@generation))
        if @state['mode']=='undo'
          Sketchup.undo
          @state['undo_issued']=true
        else
          submit_options(a)
        end
        @state['phase']='measuring'
        UI.start_timer(POLL_DELAY,false) { MH::ModuleStudio::NativeAutoRedrawCheck.phase_measure }
        nil
      rescue StandardError=>error
        fail_phase(error.message)
      end

      # Mirrors the verified NativeReplaceProfile edit: rows carry a symbol and
      # the value is written before edit_variables recomputes the rule.
      def submit_options(root)
        rule=Core.rule!(JSON.parse(root.get_attribute(Reader::DICT,'rule_json')))
        rows=Parametric.variables(rule)
        row=rows.find { |item| item['symbol'].to_s=='T1' || item[:symbol].to_s=='T1' }
        return fail_phase('Không tìm thấy tham số T1.') unless row
        row['value']=EDITED_THICKNESS
        edited=Parametric.edit_variables(rule,rows)
        targets=Parametric.targets(edited)
        @state['edited_targets']=targets.length
        UpdateWork.submit(@model,key: :options,complete:method(:options_done)) do
          Runtime.update_trial(root,edited,targets)
        end
      end

      def options_done(status,error)
        return unless @state
        @state['options']={'status'=>status.to_s,'error'=>error&.message}
      end

      def phase_measure(attempt=0)
        return unless @state && @state['phase']=='measuring'
        return unless Sketchup.active_model.equal?(@model)
        if UpdateWork.pending?(@model) || ScaleRedraw.pending?(@model)
          return fail_phase('Quá hạn chờ redraw.') if attempt>200
          UI.start_timer(POLL_DELAY,false) { MH::ModuleStudio::NativeAutoRedrawCheck.phase_measure(attempt+1) }
          return
        end
        a,b=@roots
        @state['after']={'a'=>thickness(a),'b'=>thickness(b)}
        @state['geometry_after']=root_frames
        @state['rule_validity']={'a'=>rule_validity(a),'b'=>rule_validity(b)}
        @state['update_pending']=UpdateWork.pending?(@model)
        @state['scale_pending']=ScaleRedraw.pending?(@model)
        @state['phase']='done'
        nil
      rescue StandardError=>error
        fail_phase(error.message)
      end

      def thickness(root)
        return nil unless root&.valid?
        bounds=root.bounds
        spans=[bounds.width,bounds.height,bounds.depth].map { |value| (value*MM).round(3) }
        local=root.definition.bounds
        local_spans=[local.width,local.height,local.depth].map { |value| (value*MM).round(3) }
        {'frame'=>'model axis-aligned root.bounds','units'=>'mm',
         'spans_mm'=>spans,'min_mm'=>spans.min,
         'local_frame'=>'definition.bounds','local_spans_mm'=>local_spans,
         'origin_mm'=>origin(root)}
      end

      def origin(root)
        root.transformation.origin.to_a.map { |value| (value*MM).round(3) }
      end

      def root_frames
        a,b=@roots
        {'a_origin_mm'=>a && origin(a),'b_origin_mm'=>b && origin(b),
         'a_scale'=>a && ScaleRedraw.signature(a),'b_scale'=>b && ScaleRedraw.signature(b)}
      end

      def rule_validity(root)
        _root,_rule,calculation=ScaleRedraw.prepare(root)
        {'changed_count'=>calculation['changed_count']}
      rescue StandardError=>error
        {'error'=>error.message}
      end

      def report
        return {'started'=>false} unless @state
        {'started'=>true,'verdict'=>verdict,'state'=>@state}
      end

      def verdict
        return {'passed'=>false,'reason'=>'chưa hoàn tất'} unless @state['phase']=='done'
        before=@state['before'];after=@state['after'];scaled=@state['after_scale']
        expected_a=@state['mode']=='undo' ? SOURCE_THICKNESS : EDITED_THICKNESS
        checks={
          'a_thickness'=>near?(after['a'],expected_a),
          'b_restored'=>same_spans?(before['b'],after['b']),
          'b_scaled_before'=>scaled_before?(before['b'],scaled['b']),
          'b_offset_kept'=>before['b']['origin_mm'].zip(after['b']['origin_mm'])
            .all? { |left,right| (left-right).abs<=TOLERANCE },
          'rule_valid_a'=>@state.dig('rule_validity','a','changed_count')==0,
          'rule_valid_b'=>@state.dig('rule_validity','b','changed_count')==0,
          'quiet'=>!@state['update_pending'] && !@state['scale_pending']
        }
        {'passed'=>checks.values.all?,'checks'=>checks,'expected_a_mm'=>expected_a}
      end

      def near?(row,value)
        return false unless row
        (row['min_mm']-value).abs<=TOLERANCE
      end

      def scaled_before?(before,scaled)
        return false unless before && scaled
        ratios=before['spans_mm'].zip(scaled['spans_mm']).map do |left,right|
          left.abs<0.001 ? 1.0 : right/left
        end
        ratios.count { |ratio| (ratio-SCALE_RATIO).abs<0.05 }==1 &&
          ratios.all? { |ratio| (ratio-1.0).abs<0.05 || (ratio-SCALE_RATIO).abs<0.05 }
      end

      def same_spans?(before,after)
        return false unless before && after
        before['spans_mm'].zip(after['spans_mm']).all? { |left,right| (left-right).abs<=TOLERANCE }
      end

      def cleanup
        return {'cleaned'=>false,'reason'=>'chưa chạy'} unless @state
        return {'cleaned'=>false,'reason'=>'còn job đang chạy'} if @model && (UpdateWork.pending?(@model) || ScaleRedraw.pending?(@model))
        model=@model
        ids=Array(@state['roots'])
        erased=[]
        definitions_removed=0
        operation=false
        begin
          model.start_operation('MH QA Auto Redraw Cleanup',true)
          operation=true
          ids.each do |id|
            entity=model.entities.to_a.find { |item| item.persistent_id.to_s==id }
            next unless entity
            erased << id
            entity.erase!
          end
          loop do
            target=model.definitions.to_a.find do |definition|
              !Array(@definitions_before).include?(definition.persistent_id) &&
                definition.instances.empty? && !(definition.respond_to?(:image?) && definition.image?)
            end
            break unless target
            model.definitions.remove(target)
            definitions_removed+=1
          end
          model.commit_operation
          operation=false
        rescue StandardError=>error
          model.abort_operation if operation
          return {'cleaned'=>false,'error'=>error.message,'erased'=>erased}
        end
        materials_removed=remove_new_materials(model)
        leftover={
          'owned'=>ids.reject { |id| erased.include?(id) },
          'update_pending'=>UpdateWork.pending?(model),
          'scale_pending'=>ScaleRedraw.pending?(model),
          'scale_pending_roots'=>ScaleRedraw.pending?(model)
        }
        preservation={
          'camera'=>camera_state(model)==@camera,
          'selection'=>model.selection.to_a.map(&:entityID)==@selection,
          'materials'=>@materials_before.all? { |name| model.materials[name] },
          'definitions'=>@definitions_before.all? { |id| model.definitions.to_a.any? { |d| d.persistent_id==id } }
        }
        @state['phase']='cleaned'
        @state['leftover']=leftover
        @state['preservation']=preservation
        {'cleaned'=>true,'erased'=>erased,'definitions_removed'=>definitions_removed,
         'materials_removed'=>materials_removed,'leftover'=>leftover,'preservation'=>preservation}
      end

      def remove_new_materials(model)
        added=model.materials.to_a.reject { |material| @materials_before.include?(material.name) }
        added.count do |material|
          used=model.entities.to_a.any? { |entity| material_used?(material,entity) }
          next false if used
          model.materials.remove(material)
          true
        rescue StandardError
          false
        end
      end

      def material_used?(material,entity)
        return false unless entity.respond_to?(:material)
        return true if material.used_by?(entity)
        definition=entity.respond_to?(:definition) ? entity.definition : nil
        return false unless definition
        definition.entities.to_a.any? { |child| material.used_by?(child) }
      rescue StandardError
        true
      end

      def camera_state(model)
        view=model.active_view
        return nil unless view
        camera=view.camera
        {'eye'=>camera.eye.to_a,'target'=>camera.target.to_a,'up'=>camera.up.to_a,
         'perspective'=>camera.perspective?,'fov'=>camera.fov}
      end

      def asset_path
        File.join(ROOT,ASSET_REL).tr('\\','/')
      end

      def private_library(path)
        library=Library.allocate
        library.instance_variable_set(:@config,{})
        library.instance_variable_set(:@publisher,nil)
        library.instance_variable_set(:@catalog,{
          'root'=>ROOT,'folders'=>[],'entries'=>[asset_row(path)]
        })
        library
      end

      def asset_row(path)
        refuse!("Asset ngoài thư mục QA: #{path}") unless path.start_with?(ROOT)
        {'id'=>ENTRY_ID,'name'=>'Canh phai QA','folder'=>'Canh','path'=>path,
         'fingerprint'=>LibraryCatalog.fingerprint(path),'bytes'=>File.size(path)}
      end

      def refuse!(message)
        raise message
      end

      def fail_phase(message)
        @state['phase']='error'
        @state['error']=message
        nil
      end
    end
  end
end
