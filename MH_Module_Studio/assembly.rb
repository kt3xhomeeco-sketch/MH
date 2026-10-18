# encoding: UTF-8
require_relative 'scale_redraw'
require_relative 'assembly_math'
require_relative 'assembly_containers'
require_relative 'assembly_contacts'
require_relative 'assembly_envelope'
require_relative 'assembly_external'
require_relative 'assembly_parameters'
require_relative 'import_links'

module MH
  module ModuleStudio
    # Native assembly adapter. Records reference instances, never shared definition
    # identities; panel anchors follow their current bounds after ATT redraw.
    module Assembly
      extend self
      KEY = 'assembly_links_v1'.freeze
      attr_reader :last_error

      def records(model, except: [])
        AssemblyContainers.records(model,except:except)
      end

      def root(model, anchor)
        AssemblyContainers.resolve(model,anchor)
      end

      def container?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      def panel(model, anchor)
        item = root(model, anchor)
        transform = item.transformation
        if anchor['part'] || anchor['panel']
          matches = []
          visit = lambda do |parent, frame, depth|
            raise Core::Error, 'Cấu trúc module quá sâu.' if depth > 30
            parent.definition.entities.each do |child|
              next unless container?(child)
              child_frame = frame * child.transformation
              match = anchor['part'] ? child.get_attribute(Reader::DICT,'part_key')==anchor['part'] : child.get_attribute(Reader::DICT,AssemblyContainers::PANEL)==anchor['panel']
              matches << [child, child_frame] if match
              visit.call(child, child_frame, depth + 1)
            end
          end
          visit.call(item, transform, 0)
          raise Core::Error, 'Không tìm được duy nhất tấm đã liên kết.' unless matches.length == 1
          item, transform = matches.first
        else
          anchor.fetch('path', []).each do |pid|
            child = item.definition.entities.find { |entry| entry.persistent_id.to_s == pid }
            raise Core::Error, 'Tấm tham chiếu đã thay đổi cấu trúc; chọn lại mặt.' unless container?(child)
            item = child
            transform *= child.transformation
          end
        end
        [item, transform]
      end

      def plane(model, anchor)
        item, frame = panel(model, anchor)
        bounds = item.definition.bounds
        axis = anchor.fetch('axis'); side = anchor.fetch('side')
        raise Core::Error, 'Mặt tham chiếu không hợp lệ.' unless [0, 1, 2].include?(axis) && [0, 1].include?(side)
        low = bounds.min.to_a; high = bounds.max.to_a
        others = [0, 1, 2] - [axis]
        points = [[0,0],[1,0],[1,1],[0,1]].map do |pair|
          point = low.dup
          point[axis] = side.zero? ? low[axis] : high[axis]
          others.each_with_index { |other, i| point[other] = pair[i].zero? ? low[other] : high[other] }
          Geom::Point3d.new(point).transform(frame).to_a.map { |value| value * 25.4 }
        end
        normal = AssemblyMath.unit(AssemblyMath.cross(AssemblyMath.sub(points[1], points[0]), AssemblyMath.sub(points[2], points[0])))
        local_axis = [0,0,0]; local_axis[axis] = side.zero? ? -1 : 1
        desired = Geom::Vector3d.new(local_axis).transform(frame).to_a
        normal = AssemblyMath.mul(normal, -1) if AssemblyMath.dot(normal, desired).negative?
        { 'point' => 3.times.map { |i| points.sum { |point| point[i] } / 4 }, 'normal' => normal, 'points' => points }
      end

      def anchor(path)
        face = path.last
        chain, scope = AssemblyContainers.pick_chain(path)
        raise Core::Error, 'Chọn mặt nằm trong group/component của module.' unless face.is_a?(Sketchup::Face) && chain.all? { |item| container?(item) } && !chain.empty?
        item = chain.last
        axis = face.normal.to_a.map(&:abs).each_with_index.max[1]
        raise Core::Error, 'Chọn mặt phẳng theo trục của tấm hộp.' if face.normal.to_a[axis].abs < 0.999999
        bounds = item.definition.bounds
        value = face.vertices.first.position.to_a[axis]
        side = (value - bounds.min.to_a[axis]).abs < (value - bounds.max.to_a[axis]).abs ? 0 : 1
        boundary = side.zero? ? bounds.min.to_a[axis] : bounds.max.to_a[axis]
        raise Core::Error, 'Mặt này không phải mặt biên của tấm.' if (value - boundary).abs > 0.001
        part = item.get_attribute(Reader::DICT, 'part_key') if chain.length > 1
        { 'root' => chain.first.persistent_id.to_s, 'scope'=>scope, 'part' => part,
          'panel'=>item.get_attribute(Reader::DICT,AssemblyContainers::PANEL),
          'path' => chain.drop(1).map { |entry| entry.persistent_id.to_s }, 'axis' => axis, 'side' => side,
          'name' => [chain.first.name, item.name].reject(&:empty?).uniq.join(' / ') }.compact
      end

      def world_plane(model, anchor)
        result = plane(model,anchor)
        frame = AssemblyContainers.frame(model,anchor)
        result['points'] = result['points'].map { |point| Geom::Point3d.new(point.map { |v| v/25.4 }).transform(frame).to_a.map { |v| v*25.4 } }
        result['point'] = Geom::Point3d.new(result['point'].map { |v| v/25.4 }).transform(frame).to_a.map { |v| v*25.4 }
        result['normal'] = Geom::Vector3d.new(result['normal']).transform(frame).normalize.to_a
        result
      end

      def world_transform(model, anchor)
        AssemblyContainers.frame(model,anchor)*root(model,anchor).transformation
      end

      def projection(entity, normal)
        bounds = entity.definition.bounds
        points = 8.times.map { |i| bounds.corner(i).transform(entity.transformation).to_a.map { |value| value * 25.4 } }
        points.map { |point| AssemblyMath.dot(point, normal) }.minmax
      end

      def transformation(entity)
        entity.transformation
      end

      def rotate(entity,point,axis,radians)
        entity.transform!(Geom::Transformation.rotation(Geom::Point3d.new(point),axis,radians))
      end

      def translate(entity, vector)
        return if AssemblyMath.dot(vector, vector) < 1.0e-12
        entity.transform!(Geom::Transformation.translation(vector.map { |value| value / 25.4 }))
      end

      def distance(model, record)
        return AssemblyExternal.new(model,record['b']).distance(model,record) if record['external']
        return Core.number(record.fetch('gap', 0)) unless record['r1'] && record['r2']
        a = plane(model, record['r1']); b = plane(model, record['r2'])
        low, high = AssemblyMath.interval(a, b)
        high - low
      end

      def resize(entity, normal, size)
        axes = [entity.transformation.xaxis, entity.transformation.yaxis, entity.transformation.zaxis]
        axis = axes.each_index.max_by { |i| AssemblyMath.dot(axes[i].normalize.to_a, normal).abs }
        AssemblyMath.parallel!(axes[axis].to_a, normal)
        current = projection(entity, normal)
        factor = size / (current[1] - current[0])
        return if (factor - 1).abs < 1.0e-8
        if entity.attribute_dictionary('dynamic_attributes', false) || entity.definition.attribute_dictionary('dynamic_attributes', false)
          raise Core::Error, 'Chuyển DC sang module Studio trước khi dùng Vừa khoang.'
        end
        factors = [1.0,1.0,1.0]; factors[axis] = factor
        entity.transformation *= Geom::Transformation.scaling(ORIGIN, *factors)
        if AssemblyContainers.managed?(entity)
          AssemblyExternal.resize_assembly(entity)
        elsif entity.get_attribute(Reader::DICT, 'trial', false)
          ScaleRedraw.apply(entity.model, [ScaleRedraw.prepare(entity)])
        end
      end

      def repeat_axis(entity, record)
        direction = AssemblyMath::DIRECTIONS.fetch(record.fetch('direction', 'right'))
        AssemblyMath.unit(Geom::Vector3d.new(direction).transform(entity.transformation).to_a)
      end

      def repeat_plan(model, record)
        entity = root(model, record['b'])
        normal = repeat_axis(entity, record)
        bounds = projection(entity, normal)
        interval = if record['equal']
                     AssemblyMath.interval(plane(model, record.fetch('a')), plane(model, record.fetch('c')), normal)
                   end
        layout = AssemblyMath.repeat_layout(count: record['count'], size: bounds[1] - bounds[0], start: bounds[0],
          gap: distance(model, record), interval: interval, ends: record.fetch('ends', true))
        [normal, bounds, layout]
      end

      def apply_repeat(model, record)
        source = root(model, record['b'])
        normal, bounds, layout = repeat_plan(model, record)
        copies = record.fetch('copies', []).map { |pid| root(model, AssemblyContainers.ref(record,pid)) }
        needed = layout['positions'].length - 1
        copies.pop.erase! while copies.length > needed
        while copies.length < needed
          parent_entities = source.parent==model ? model.active_entities : source.parent.entities
          copy = parent_entities.add_instance(source.definition, source.transformation)
          copy.name = source.name
          copy.material = source.material; copy.layer = source.layer
          if source.get_attribute(Reader::DICT, 'trial', false)
            Runtime.private_tree(copy)
            rule = Core.rule!(JSON.parse(source.get_attribute(Reader::DICT, 'rule_json')))
            values = JSON.parse(source.get_attribute(Reader::DICT, 'parameter_values_json', '{}'))
            logical = source.get_attribute(Reader::DICT,'formula_envelope_json')
            copy.set_attribute(Reader::DICT,'formula_envelope_json',logical) if logical
            _snapshot, bindings = Reader.live(copy, label: copy.name, parameter: Runtime.read_parameter(rule, values))
            Runtime.stamp(copy, rule, bindings, values)
          end
          copies << copy
        end
        frame = source.transformation
        [source, *copies].each_with_index do |entity, index|
          entity.transformation = frame
          translate(entity, AssemblyMath.mul(normal, layout['positions'][index] - bounds[0]))
        end
        record['copies'] = copies.map { |entity| entity.persistent_id.to_s }
      end

      def apply_record(model, record)
        space = record['external'] ? AssemblyExternal.new(model,record['b']) : self
        entity = space.root(model, record.fetch('b'))
        mode = record.fetch('mode')
        raise Core::Error, 'Kiểu liên kết không hợp lệ.' unless AssemblyMath::MODES.include?(mode)
        return apply_repeat(model, record) if mode == 'repeat'
        a = space.plane(model, record.fetch('a')); b = space.plane(model, record.fetch('b'))
        case mode
        when 'contact'
          space.translate(entity, AssemblyMath.offset(a, b, space.distance(model, record)))
        when 'center', 'fit'
          c = space.plane(model, record.fetch('c'))
          result = AssemblyMath.centered(a, c, space.projection(entity, a['normal']), clearance: mode == 'fit' ? space.distance(model, record) : nil)
          space.resize(entity, a['normal'], result['size']) if mode == 'fit'
          current = space.projection(entity, a['normal'])
          result = AssemblyMath.centered(a, c, current)
          space.translate(entity, AssemblyMath.mul(a['normal'], result['delta']))
        when 'angle'
          turn = AssemblyMath.rotation(a['normal'], b['normal'], record['angle'])
          return if turn['radians'].abs < 1.0e-9
          pivot = Geom::Point3d.new(b['point'].map { |value| value / 25.4 })
          space.rotate(entity,pivot.to_a,turn['axis'],turn['radians'])
        end
      end

      def verify(model, record)
        space = record['external'] ? AssemblyExternal.new(model,record['b']) : self
        b = space.root(model, record['b'])
        if record['mode'] == 'repeat'
          normal, _bounds, layout = repeat_plan(model, record)
          entities = [b, *record.fetch('copies').map { |pid| root(model, AssemblyContainers.ref(record,pid)) }]
          raise Core::Error, 'Số bản lặp không khớp.' unless entities.length == layout['positions'].length
          entities.zip(layout['positions']).each do |entity, coordinate|
            raise Core::Error, 'Liên kết lặp bị xung đột.' if (projection(entity, normal)[0] - coordinate).abs > 0.02
            reference = projection(b, normal)
            actual = projection(entity, normal)
            if ((actual[1]-actual[0]) - (reference[1]-reference[0])).abs > 0.02
              raise Core::Error, 'Các bản lặp cần cùng kích thước theo phương lặp.'
            end
          end
        elsif record['mode'] == 'angle'
          a = space.plane(model, record['a']); target = space.plane(model, record['b'])
          turn = AssemblyMath.rotation(a['normal'], target['normal'], record['angle'])
          raise Core::Error, 'Liên kết góc bị xung đột.' if turn['radians'].abs > 1.0e-6
        elsif record['mode'] == 'contact'
          delta = AssemblyMath.offset(space.plane(model, record['a']), space.plane(model, record['b']), space.distance(model, record))
          raise Core::Error, 'Các liên kết khoảng cách bị xung đột.' if AssemblyMath.dot(delta, delta) > 0.0004
        else
          a = space.plane(model, record['a']); c = space.plane(model, record['c'])
          result = AssemblyMath.centered(a, c, space.projection(b, a['normal']), clearance: record['mode'] == 'fit' ? space.distance(model, record) : nil)
          bounds = space.projection(b, a['normal'])
          raise Core::Error, 'Liên kết căn giữa/vừa khoang bị xung đột.' if result['delta'].abs > 0.02 || (result['size'] - bounds[1] + bounds[0]).abs > 0.02
        end
      end

      def transact(model, proposed, transparent: false, motion: nil, group_record: nil, updates: [], mutable_anchors: [], envelope_requests: {}, replacement: nil)
        Runtime.ensure_assembly_context(model)
        @busy = true
        model.start_operation('MH Liên Kết Module', true, false, transparent)
        operation = true
        previous_links = replacement ? Core.copy_data(proposed) : Assembly.records(model)
        changed = (previous_links+proposed).select { |row| previous_links.include?(row)!=proposed.include?(row) }
        edited_scopes = changed.flat_map { |row| AssemblyContainers.references(row).filter_map { |ref| ref['scope'] } }.uniq
        edited_scopes |= [motion[0]['scope']].compact if motion
        markers = updates.map { |anchor,_rule,_values| { 'scope'=>anchor['scope'],'b'=>anchor } }
        markers += mutable_anchors.map { |anchor| {'scope'=>anchor['scope'],'b'=>anchor} }
        markers << { 'scope'=>motion[0]['scope'],'b'=>motion[0] } if motion
        AssemblyContainers.independent!(model,proposed+markers)
        if group_record
          grouped = AssemblyContainers.group!(model,proposed,group_record,manual:true)
          raise Core::Error,'Cụm có liên kết phủ bì toàn cụm; giữ các cụm hiện tại để bảo toàn liên kết.' unless grouped
          AssemblyParameters.set_master(model,grouped,group_record)
        end
        AssemblyExternal.validate!(proposed)
        envelope_targets = {}
        replaced = replacement && root(model,replacement)
        scaled = AssemblyContainers.normalize_scales!(model,envelopes:envelope_targets,except:Array(replaced))
        scaled.delete(replaced) if replaced
        scaled_scopes = envelope_targets.keys
        updates.map { |anchor,*_rest| anchor['scope'] }.compact.uniq.each do |scope|
          envelope_targets[scope] ||= AssemblyEnvelope.target(AssemblyContainers.wrapper(model,scope))
        end
        raise Core::Error,'Mục tiêu phủ bì không thuộc cụm đang sửa.' unless (envelope_requests.keys-envelope_targets.keys).empty?
        envelope_requests.each { |scope,box| envelope_targets[scope] = Core.bounds!(Core.copy_data(box)) }
        ScaleRedraw.apply(model,scaled.map { |entity| ScaleRedraw.prepare(entity) }) unless scaled.empty?
        growth = {}
        updates.each do |anchor,rule,values,source|
          entity = root(model,anchor)
          before = Core.dimensions(AssemblyEnvelope.bounds(entity))
          Core.rule!(rule)
          Runtime.apply_trial_update(entity,rule,values,source:source)
          if anchor['scope']
            growth[anchor['scope']] = Array(growth[anchor['scope']]) | AssemblyEnvelope.changing_axes(entity,rule,before)
          end
        end
        yield proposed if block_given?
        AssemblyParameters.synchronize(model).each { |scope,axes| growth[scope]=Array(growth[scope]) | axes }
        ImportLinks.apply_reservations(model,proposed)
        ordered = AssemblyMath.ordered(proposed)
        translate(root(model, motion[0]), motion[1]) if motion
        solve_ordered(model,ordered)
        AssemblyEnvelope.apply(model,envelope_targets,ordered,growth:growth,fixed_scopes:scaled_scopes | envelope_requests.keys)
        ordered.each { |record| verify(model, record) }
        ImportLinks.remember_reservations(model)
        AssemblyContainers.store(model,proposed)
        (edited_scopes-envelope_targets.keys).each do |scope|
          component = model.find_entity_by_persistent_id(scope.to_i)
          next unless component && component.valid? && AssemblyContainers.managed?(component)
          AssemblyEnvelope.remember(component,AssemblyEnvelope.bounds(component))
        end
        model.commit_operation
        operation = false
        @last_error = nil
        model.active_view.invalidate
        proposed
      rescue StandardError
        if operation
          if transparent
            model.commit_operation
            Sketchup.undo
          else
            model.abort_operation
          end
        end
        raise
      ensure
        @busy = false
        @observers&.fetch(model, nil)&.reset
      end

      def solve_ordered(model,ordered)
        internal,external = ordered.partition { |record| !record['external'] }
        internal.chunk { |record| AssemblyContainers.identity(record['b']) }.each do |_pid, group|
          group.each { |record| apply_record(model, record) unless record['mode'] == 'contact' }
          AssemblyContacts.solve(model,group)
        end
        ids = AssemblyExternal.validate!(external)
        external.sort_by { |record| ids.index(record['id']) }.chunk { |record| AssemblyContainers.identity(record['b']) }.each do |_pid,group|
          group.each { |record| apply_record(model,record) unless record['mode']=='contact' }
          AssemblyContacts.solve(model,group)
          scope = group.first.dig('b','scope')
          solve_ordered(model,internal.select { |record| record['scope']==scope }) if scope
        end
      end

      def save(model, record)
        proposed = records(model)
        record = Core.copy_data(record)
        refs = AssemblyContainers.references(record)
        scopes = refs.map { |ref| ref['scope'] }.uniq
        if refs.any? { |ref| ref['level']=='assembly' } || scopes.length>1
          record['external'] = true
          record.delete('scope')
        elsif scopes.first
          record.delete('external')
          record['scope'] = scopes.first
        else
          record.delete('external'); record.delete('scope')
        end
        record['id'] ||= Core::Ids.uuid
        prior = proposed.find { |row| row['id'] == record['id'] }
        if prior && (record['mode']!=prior['mode'] || !AssemblyMath.same_surface?(record['a'],prior['a']) || !AssemblyMath.same_surface?(record['b'],prior['b']))
          record.delete('import_link')
        end
        record['copies'] = prior.fetch('copies', []) if prior
        if prior && prior['mode'] == 'repeat' && record['mode'] != 'repeat'
          raise Core::Error, 'Xóa liên kết lặp trước khi đổi sang kiểu khác.'
        end
        proposed.reject! { |row| row['id'] == record['id'] }
        proposed << record
        transact(model, proposed)
        record
      end

      def group(model, record)
        proposed = records(model)
        seed = proposed.find { |row| row['id']==record['id'] }
        raise Core::Error,'Lưu liên kết trước khi gộp.' unless seed
        transact(model,proposed,group_record:seed)
        seed
      end

      def store_contacts(model,existing,links,removed: [])
        Runtime.ensure_top_level(model)
        proposed = existing+links
        AssemblyMath.ordered(proposed)
        AssemblyExternal.validate!(proposed)
        @busy = true
        model.start_operation('MH Tự Tạo Liên Kết',true)
        operation = true
        scopes = (links+removed).flat_map { |row| AssemblyContainers.references(row).map { |ref| ref['scope'] } }.compact.uniq
        AssemblyContainers.independent!(model,proposed,scopes:scopes)
        links.each { |row| verify(model,row) }
        AssemblyContainers.store(model,proposed,scopes:scopes)
        model.commit_operation
        operation = false
        @last_error = nil
      rescue StandardError
        model.abort_operation if operation
        raise
      ensure
        @busy = false
        @observers&.fetch(model,nil)&.reset
      end

      def module_name(model, anchor)
        entity = root(model,anchor)
        name = entity.name.to_s.strip
        name.empty? ? entity.definition.name.to_s : name
      rescue Core::Error
        anchor.fetch('name','Module')
      end

      def display_record(model, record)
        display = Core.copy_data(record)
        AssemblyContainers::REFS.each do |key|
          ref = display[key]
          next unless ref
          ref['module_name'] = module_name(model,ref)
          begin
            entity = root(model,ref); part, = panel(model,ref)
            ref['name'] = [ref['module_name'],part==entity ? nil : part.name].compact.reject(&:empty?).uniq.join(' / ')
            ref['name'] += ' / '+AssemblyFacePicker.label(ref) if ref['level']
          rescue Core::Error
            # Retain stale face labels so the user can reselect the face.
          end
        end
        display
      end

      def presentation_groups(model,rows = records(model))
        rows.group_by { |row| row['scope'] }.flat_map do |scope,subset|
          owner = model.find_entity_by_persistent_id(scope.to_i) if scope
          members = owner ? AssemblyContainers.members(owner).map do |member|
            ref = {'scope'=>scope,'root'=>member.persistent_id.to_s}
            {'ref'=>ref,'name'=>module_name(model,ref)}
          end : []
          name = owner && (owner.name.to_s.empty? ? owner.definition.name : owner.name)
          AssemblyPresentation.groups(subset.map { |row| display_record(model,row) },scope:scope,members:members,name:name)
        end
      end

      def rename(model, anchor, name, record: nil)
        Runtime.ensure_assembly_context(model)
        name = name.to_s.strip
        raise Core::Error,'Tên module cần từ 1 đến 120 ký tự.' if name.empty? || name.length>120 || name.match?(/[\x00-\x1f]/)
        proposed = records(model)
        @busy = true
        model.start_operation('MH Đổi Tên Module',true)
        operation = true
        AssemblyContainers.independent!(model,proposed+[record,{'b'=>anchor,'scope'=>anchor['scope']}].compact)
        root(model,anchor).name = name
        AssemblyContainers.store(model,proposed)
        model.commit_operation
        operation = false
        @last_error = nil
        model.active_view.invalidate
      rescue StandardError
        model.abort_operation if operation
        raise
      ensure
        @busy = false
        @observers&.fetch(model,nil)&.reset
      end

      def remove(model, id)
        # Removing a relationship keeps its placed instances as ordinary modules.
        Runtime.ensure_assembly_context(model)
        current = records(model)
        proposed = current.reject { |row| row['id'] == id }
        return transact(model,proposed) if current.any? { |row| row['id']==id && row.dig('import_link','door_mount') }
        @busy = true
        model.start_operation('MH Xóa Liên Kết', true)
        operation = true
        AssemblyContainers.store(model,proposed)
        model.commit_operation
        operation = false
        @last_error = nil
      rescue StandardError
        model.abort_operation if operation
        raise
      ensure
        @busy = false
        @observers&.fetch(model, nil)&.reset
      end

      def move(model, anchor, delta)
        links = records(model)
        normals = links.filter_map do |record|
          next unless AssemblyContainers.identity(record['b']) == AssemblyContainers.identity(anchor)
          next if record['mode'] == 'angle' || (record['mode'] == 'repeat' && !record['equal'])
          if record['external']
            normal = world_plane(model,record.fetch('a'))['normal']
            Geom::Vector3d.new(normal).transform(AssemblyContainers.frame(model,anchor).inverse).normalize.to_a
          else
            plane(model, record.fetch('a'))['normal']
          end
        end
        allowed = AssemblyMath.allowed_motion(delta, normals)
        [links, allowed]
      end

      def fingerprint(model)
        data = records(model).map do |record|
          anchors = %w[a b c r1 r2].filter_map { |key| record[key] }
          planes = anchors.map { |ref| record['external'] ? world_plane(model,ref) : plane(model, ref) }
          instance_refs = [record['b'], *record.fetch('copies', []).map { |pid| AssemblyContainers.ref(record,pid) }]
          instances = instance_refs.map do |ref|
            entity = root(model, ref)
            [entity.transformation.to_a, entity.definition.bounds.min.to_a, entity.definition.bounds.max.to_a]
          end
          [record, planes, instances,AssemblyContainers.frame(model,record['b']).to_a]
        end
        JSON.generate([data,ImportLinks.reservation_fingerprint(model)])
      end

      def install
        return unless defined?(Sketchup::ModelObserver)
        @observers ||= {}
        @app_observer ||= AssemblyAppObserver.new
        Sketchup.add_observer(@app_observer) unless @installed
        @installed = true
        watch(Sketchup.active_model)
      end

      def watch(model, rebind: false)
        @observers ||= {}
        if rebind && (previous=@observers.delete(model))
          previous.reset
          model.remove_observer(previous)
        end
        @last_error=nil if rebind
        @observers[model] ||= begin
          observer = AssemblyModelObserver.new(model)
          model.add_observer(observer)
          observer
        end
      end

      if defined?(Sketchup::ModelObserver)
        class AssemblyModelObserver < Sketchup::ModelObserver
          def initialize(model)
            super()
            @model = model
            @generation = 0
            reset
          end

          def reset
            @generation += 1
            @fingerprint = Assembly.fingerprint(@model)
          rescue StandardError
            @fingerprint = nil
          end

          def onTransactionCommit(_model)
            return if Assembly.instance_variable_get(:@busy)
            generation = @generation += 1
            UI.start_timer(0.15, false) do
              next unless generation == @generation && Sketchup.active_model.equal?(@model)
              begin
                current = Assembly.fingerprint(@model)
                next if current == @fingerprint || Assembly.records(@model).empty? && ImportLinks.reservation_fingerprint(@model).empty?
                Assembly.transact(@model, Assembly.records(@model), transparent: true)
              rescue StandardError => detail
                Assembly.instance_variable_set(:@last_error, detail.message)
                Sketchup.status_text = "MH Liên kết: #{detail.message}"
              ensure
                reset
              end
            end
          end

          %i[onTransactionUndo onTransactionRedo onTransactionAbort onActivePathChanged].each do |event|
            define_method(event) { |_model| reset unless Assembly.instance_variable_get(:@busy) }
          end
        end

        class AssemblyAppObserver < Sketchup::AppObserver
          %i[onNewModel onOpenModel].each do |event|
            define_method(event) { |model| Assembly.watch(model,rebind:true) }
          end
          def onActivateModel(model)
            Assembly.watch(model)
          end
        end
      end
    end
  end
end
