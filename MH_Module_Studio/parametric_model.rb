# encoding: UTF-8
require_relative 'assembly'

module MH
  module ModuleStudio
    # Native naming/presentation only; never rewrite ATT expressions to rename.
    module ParametricModel
      extend self

      def assembly_snapshot(root)
        frame = Frames.scale_frame(root.transformation.to_a)
        parts = AssemblyContainers.members(root).flat_map do |member|
          if member.get_attribute(Reader::DICT,'trial',false)
            snapshot, = Reader.live(member,label:member.name,parameter:1)
            snapshot['parts'].map do |part|
              row = Core.copy_data(part)
              row['key'] = member.persistent_id.to_s+':'+part['key']
              row['name'] = member.name+' / '+part['name']
              row['bounds'] = Frames.box(Frames.corners(part['bounds']).map { |point| Frames.point(frame,point) })
              row
            end
          else
            bounds = Frames.box(8.times.map { |i| member.definition.bounds.corner(i).transform(member.transformation).to_a.map { |v| v*25.4 } })
            bounds = Frames.box(Frames.corners(bounds).map { |point| Frames.point(frame,point) })
            [{'key'=>member.persistent_id.to_s,'name'=>member.name,'bounds'=>bounds,'visible'=>!member.hidden?,'box_verified'=>false}]
          end
        end
        Core.snapshot!({'id'=>Core::Ids.uuid,'label'=>root.name,'parts'=>parts,'envelope'=>Core.union(parts),'dc_inputs'=>{},'parameter'=>nil,'source'=>{'kind'=>'assembly','root_pid'=>root.persistent_id.to_s}})
      end

      def assembly_sheet(root)
        {'assembly'=>true,'variables'=>[],'categories'=>Parametric::CATEGORIES,'attributes'=>[],
         'parts'=>AssemblyContainers.members(root).map do |member|
           bounds = Frames.box(8.times.map { |i| member.definition.bounds.corner(i).transform(member.transformation).to_a.map { |v| v*25.4 } })
           {'key'=>member.persistent_id.to_s,'name'=>member.name,'values'=>Core.dimensions(bounds)+bounds[0],
            'expressions'=>Array.new(6) { {'text'=>'','kind'=>'measured'} },'formulas'=>Array.new(6,'')}
         end}
      end

      def rename(model,anchor,rule,name,part_key:nil)
        Runtime.ensure_assembly_context(model)
        name = Parametric.display_name(name)
        root = Assembly.root(model,anchor)
        if AssemblyContainers.managed?(root) || !rule
          raise Core::Error,'Chọn module con để đổi tên chi tiết.' if part_key
          Assembly.rename(model,anchor,name)
          return nil
        end
        edited = Parametric.rename_display(rule,name,part_key:part_key)
        return edited unless root.get_attribute(Reader::DICT,'trial',false)
        proposed = Assembly.records(model)
        Assembly.instance_variable_set(:@busy,true)
        model.start_operation('MH Đổi Tên Parametric',true)
        operation = true
        scopes = [anchor['scope']].compact
        AssemblyContainers.independent!(model,proposed+[{'b'=>anchor}],scopes:scopes)
        root = Assembly.root(model,anchor)
        Runtime.private_tree(root)
        values = JSON.parse(root.get_attribute(Reader::DICT,'parameter_values_json','{}'))
        edited = Parametric.with_values(edited,values)
        _current,bindings = Reader.live(root,label:root.name,parameter:Runtime.read_parameter(edited,values))
        Runtime.stamp(root,edited,bindings,values)
        AssemblyContainers.store(model,proposed,scopes:scopes) unless scopes.empty?
        model.commit_operation
        operation = false
        edited
      rescue StandardError
        model.abort_operation if operation
        raise
      ensure
        Assembly.instance_variable_set(:@busy,false)
        Assembly.watch(model).reset
        ScaleRedraw.watch(model).reset
      end
    end
  end
end
