# encoding: UTF-8
require_relative 'runtime'

module MH
  module ModuleStudio
    # The solver works in one component's coordinates. Persistence and reparenting
    # belong here, so grouping cannot change internal ATT calculation methods.
    module AssemblyContainers
      extend self
      KEY = 'assembly_links_v1'.freeze
      FLAG = 'assembly_component'.freeze
      MEMBER = 'assembly_member_key'.freeze
      PANEL = 'assembly_panel_key'.freeze
      REFS = %w[a b c r1 r2].freeze

      def managed?(entity)
        (entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)) && entity.get_attribute(Reader::DICT,FLAG,false)
      end

      def containers(model)
        model.entities.select { |entity| managed?(entity) } # rubocop:disable SketchupSuggestions/ModelEntities -- Assembly wrappers live at model level.
      end

      def read(owner)
        raw = owner.get_attribute(Reader::DICT,KEY,'[]')
        raise Core::Error,'Dữ liệu liên kết quá lớn.' unless raw.is_a?(String) && raw.bytesize <= 1024*1024
        rows = JSON.parse(raw)
        raise Core::Error,'Dữ liệu liên kết không hợp lệ.' unless rows.is_a?(Array) && rows.length <= 200
        rows
      end

      def records(model, except: [])
        result = read(model)
        containers(model).each do |wrapper|
          next if except.include?(wrapper)
          scope = wrapper.persistent_id.to_s
          read(wrapper).each do |record|
            record['id'] = scope+':'+local_id(record['id'])
            record['scope'] = scope
            REFS.each { |key| record[key]['scope'] = scope if record[key] }
            result << record
          end
        end
        # Keep stored records intact for Undo. Missing modules are absent from
        # every operational view/solver; locked modules are still real members.
        result.select { |record| REFS.filter_map { |key| record[key] }.all? { |anchor| reference_present?(model,anchor) } }
      end

      # Transactions hide erased instances from solvers, but a door link can
      # still carry the host's original envelope target needed for restoration.
      def dangling_door_links(model)
        result=read(model).select { |record| record.dig('import_link','door_relation') || record.dig('import_link','door_mount') }
        containers(model).each do |wrapper|
          scope=wrapper.persistent_id.to_s
          read(wrapper).each do |record|
            next unless record.dig('import_link','door_relation') || record.dig('import_link','door_mount')
            copy=Core.copy_data(record);copy['id']=scope+':'+local_id(copy['id']);copy['scope']=scope
            REFS.each { |key| copy[key]['scope']=scope if copy[key] }
            result << copy
          end
        end
        result.select do |record|
          host=record['a'];door=record['b']
          host && door && reference_present?(model,host) && !reference_present?(model,door)
        end
      end

      def reference_present?(model, anchor)
        return false unless anchor.is_a?(Hash) && anchor['root']
        if anchor['scope']
          owner=model.find_entity_by_persistent_id(anchor['scope'].to_i)
          return false unless owner && managed?(owner) && !owner.deleted? && owner.parent==model
          entity=owner.definition.entities.find { |item| item.persistent_id.to_s==anchor['root'] }
        else
          entity=model.find_entity_by_persistent_id(anchor['root'].to_i)
          return false unless entity && entity.parent==model
        end
        entity && (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) && !entity.deleted?
      end

      def local_id(id)
        id.to_s.split(':',2).last
      end

      def wrapper(model, scope)
        entity = model.find_entity_by_persistent_id(scope.to_i)
        raise Core::Error,'Component liên kết đã bị xóa hoặc thay cấu trúc.' unless managed?(entity) && entity.parent==model
        raise Core::Error,'Component liên kết đang bị khóa.' if entity.locked?
        entity
      end

      def frame(model, anchor)
        anchor['scope'] ? wrapper(model,anchor['scope']).transformation : Geom::Transformation.new
      end

      def resolve(model, anchor)
        if anchor['scope']
          parent = wrapper(model,anchor['scope'])
          entity = parent.definition.entities.find { |item| item.persistent_id.to_s==anchor['root'] }
        else
          entity = model.find_entity_by_persistent_id(anchor.fetch('root').to_i)
          entity = nil unless entity && entity.parent==model
        end
        unless entity && (entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)) && !entity.deleted?
          raise Core::Error,'Module liên kết đã bị xóa hoặc chuyển sang nhóm khác.'
        end
        raise Core::Error,'Module liên kết đang bị khóa.' if entity.locked?
        entity
      end

      def pick_chain(path)
        chain = path[0...-1]
        scope = managed?(chain.first) ? chain.shift.persistent_id.to_s : nil
        raise Core::Error,'Chọn một module bên trong component liên kết.' if chain.empty?
        [chain,scope]
      end

      def ref(record, pid)
        { 'root'=>pid,'scope'=>record['scope'] }.compact
      end

      def identity(anchor)
        [anchor['scope'],anchor['root']]
      end

      def references(record)
        REFS.filter_map { |key| record[key] }+record.fetch('copies',[]).map { |pid| ref(record,pid) }
      end

      def store(model, records, scopes: nil)
        model.set_attribute(Reader::DICT,KEY,JSON.generate(records.reject { |record| record['scope'] }))
        containers(model).each do |component|
          scope = component.persistent_id.to_s
          next if scopes && !scopes.include?(scope)
          local = records.select { |record| record['scope']==scope }.map do |record|
            row = Core.copy_data(record)
            row['id'] = local_id(row['id']); row.delete('scope')
            REFS.each { |key| row[key].delete('scope') if row[key] }
            row
          end
          component.set_attribute(Reader::DICT,KEY,JSON.generate(local))
        end
      end

      def members(component)
        component.definition.entities.select { |entity| entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group) }
      end

      def member_key(entity)
        key = entity.get_attribute(Reader::DICT,MEMBER)
        unless key
          key = Core::Ids.uuid
          entity.set_attribute(Reader::DICT,MEMBER,key)
        end
        key
      end

      def independent!(model, records, scopes: nil)
        containers(model).sort_by(&:persistent_id).reverse_each do |component|
          next if scopes && !scopes.include?(component.persistent_id.to_s)
          next unless component.definition.instances.length>1
          scope = component.persistent_id.to_s
          children = members(component)
          missing_keys = children.select { |entity| entity.get_attribute(Reader::DICT,MEMBER).nil? }.map do |entity|
            [entity,!entity.attribute_dictionary(Reader::DICT,false).nil?]
          end
          before = children.to_h { |entity| [entity.persistent_id.to_s,member_key(entity)] }
          component.make_unique
          # Temporary correspondence keys must not leak into the original
          # shared definition used by unselected assembly copies.
          missing_keys.each do |entity,had_dictionary|
            had_dictionary ? entity.delete_attribute(Reader::DICT,MEMBER) : entity.delete_attribute(Reader::DICT)
          end
          after = members(component).to_h { |entity| [member_key(entity),entity.persistent_id.to_s] }
          # The active record and a rename/motion marker may share the same
          # anchor Hash. Remap each object once, before any alias sees a new PID.
          anchors = records.flat_map { |record| REFS.filter_map { |key| record[key] } }.uniq(&:object_id)
          anchors.each do |anchor|
            next unless anchor['scope']==scope
            anchor['root'] = after.fetch(before.fetch(anchor['root']))
          end
          copies = records.filter_map { |record| record['copies'] if record['scope']==scope }.uniq(&:object_id)
          copies.each { |pids| pids.map! { |pid| after.fetch(before.fetch(pid)) } }
        end
      end

      def normalize_scales!(model,envelopes: nil,except: [])
        containers(model).reject { |component| except.include?(component) }.flat_map { |component| normalize_component!(component,envelopes:envelopes) }
      end

      def normalize_component!(component,envelopes: nil)
        frame = Geom::Transformation.new(Frames.scale_frame(component.transformation.to_a))
        return [] if [0,5,10].all? { |index| (frame.to_a[index]-1).abs < 1.0e-8 }
        if envelopes
          component.definition.invalidate_bounds
          box = [component.definition.bounds.min.to_a,component.definition.bounds.max.to_a]
          envelopes[component.persistent_id.to_s] = Frames.box(Frames.corners(box).map { |point| Frames.point(frame.to_a,point).map { |value| value*25.4 } })
        end
        children = members(component)
        children.each { |child| child.transformation = frame*child.transformation }
        component.transformation *= frame.inverse
        children.select { |child| child.get_attribute(Reader::DICT,'trial',false) }
      end

      def connected(records, seed)
        included = references(seed).map { |anchor| identity(anchor) }
        loop do
          previous = included.dup
          scopes = included.map(&:first).compact
          records.each do |record|
            refs = references(record).map { |anchor| identity(anchor) }
            included |= refs if refs.any? { |key| included.include?(key) || scopes.include?(key[0]) && key[0] }
          end
          break if included==previous
        end
        included
      end

      def group!(model, records, seed, manual: false)
        seed_refs = references(seed)
        seed_scopes = seed_refs.map { |ref| ref['scope'] }.uniq
        if !seed['external'] && seed_scopes.length==1 && seed_scopes.first
          scope = seed_scopes.first
          seed['scope'] = scope; seed['id'] = scope+':'+local_id(seed['id'])
          return wrapper(model,scope)
        end
        included = connected(records,seed)
        external_scopes = records.select { |row| row['external'] }.flat_map do |row|
          references(row).filter_map { |anchor| anchor['level']=='assembly' ? anchor['root'] : nil }
        end
        touching_external = records.select { |row| row['external'] && references(row).any? { |ref| included.include?(identity(ref)) } }
        whole_assembly = touching_external.any? { |row| references(row).any? { |ref| ref['level']=='assembly' } }
        if whole_assembly || (!manual && (seed['external'] || !touching_external.empty?)) || included.any? { |scope,_pid| external_scopes.include?(scope) }
          seed['external'] = true
          seed.delete('scope')
          return nil
        end
        scopes = included.map(&:first).compact.uniq
        if scopes.length==1 && included.all? { |scope,_pid| scope==scopes.first }
          scope = scopes.first
          records.each do |record|
            next if record['external']
            next unless references(record).any? { |anchor| anchor['scope']==scope }
            record['scope'] = scope
            record['id'] = scope+':'+local_id(record['id'])
          end
          return wrapper(model,scope)
        end
        Runtime.ensure_top_level(model)
        old_wrappers = scopes.map { |scope| wrapper(model,scope) }
        roots = included.select { |scope,_pid| scope.nil? }.map { |_scope,pid| resolve(model,'root'=>pid) }
        roots += old_wrappers.flat_map { |component| members(component) }
        roots.uniq!
        raise Core::Error,'Không có module để tạo component liên kết.' if roots.empty?
        selected_records = records.select do |record|
          references(record).any? { |anchor| included.include?(identity(anchor)) || scopes.include?(anchor['scope']) && anchor['scope'] }
        end
        # Raw groups need a panel key too: reparenting is allowed to change PIDs.
        selected_records.each do |record|
          REFS.each do |key|
            anchor = record[key]
            next unless anchor && !anchor['part'] && !anchor['panel'] && !anchor.fetch('path',[]).empty?
            entity, = Assembly.panel(model,anchor)
            id = entity.get_attribute(Reader::DICT,PANEL) || Core::Ids.uuid
            entity.set_attribute(Reader::DICT,PANEL,id)
            anchor['panel'] = id
          end
        end
        seen = []
        roots.each do |entity|
          key = member_key(entity)
          if seen.include?(key)
            key = Core::Ids.uuid
            entity.set_attribute(Reader::DICT,MEMBER,key)
          end
          seen << key
        end
        mapping = {}
        selected_records.each { |record| references(record).each { |anchor| mapping[identity(anchor)] = member_key(resolve(model,anchor)) } }
        old_name = old_wrappers.first&.name
        old_master=old_wrappers.filter_map { |owner| owner.get_attribute(Reader::DICT,AssemblyParameters::KEY) }.first
        # Only explode our own wrappers, never a module or a panel definition.
        old_wrappers.each { |component| raise Core::Error,'Không chuyển được component liên kết.' unless component.explode }
        all = model.active_entities.select { |entity| (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) && seen.include?(entity.get_attribute(Reader::DICT,MEMBER)) }
        raise Core::Error,'Không giữ được đủ các module khi gom component.' unless all.length==roots.length
        component = model.active_entities.add_group(all).to_component # rubocop:disable SketchupSuggestions/AddGroup -- SketchUp 2025 reparents actual modules without reconstructing their attributes.
        component.name = old_name.to_s.empty? ? 'MH Cụm Module' : old_name
        component.definition.name = component.name
        component.set_attribute(Reader::DICT,FLAG,true)
        component.set_attribute(Reader::DICT,AssemblyParameters::KEY,old_master) if old_master
        new_scope = component.persistent_id.to_s
        children = members(component).to_h { |entity| [member_key(entity),entity.persistent_id.to_s] }
        selected_records.each do |record|
          old_scope = record['scope']
          record.delete('external')
          REFS.each do |key|
            anchor = record[key]
            next unless anchor
            anchor['root'] = children.fetch(mapping.fetch(identity(anchor)))
            anchor['scope'] = new_scope
          end
          record['copies']&.map! { |pid| children.fetch(mapping.fetch([old_scope,pid])) }
          record['scope'] = new_scope
          record['id'] = new_scope+':'+local_id(record['id'])
        end
        model.selection.clear
        model.selection.add(component)
        component
      end
    end
  end
end
