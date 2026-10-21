# encoding: UTF-8
module MH
  module ModuleStudio
    # Model-space adapter for links involving whole assemblies. Each existing
    # assembly remains an intact component with its own local internal links.
    class AssemblyExternal
      def initialize(model,anchor)
        @model = model; @anchor = anchor
      end

      def root(model,anchor)
        Assembly.root(model,anchor)
      end

      def plane(model,anchor)
        Assembly.world_plane(model,anchor)
      end

      def parent_frame
        AssemblyContainers.frame(@model,@anchor)
      end

      def transformation(entity)
        parent_frame*entity.transformation
      end

      def projection(entity,normal)
        frame = transformation(entity)
        8.times.map { |index| AssemblyMath.dot(entity.definition.bounds.corner(index).transform(frame).to_a.map { |value| value*25.4 },normal) }.minmax
      end

      def translate(entity,delta)
        vector = Geom::Vector3d.new(delta).transform(parent_frame.inverse).to_a
        Assembly.translate(entity,vector)
      end

      def resize(entity,normal,size)
        world_low,world_high = projection(entity,normal)
        local = Geom::Vector3d.new(normal).transform(parent_frame.inverse).normalize.to_a
        low,high = Assembly.projection(entity,local)
        Assembly.resize(entity,local,(high-low)*size/(world_high-world_low))
      end

      def rotate(entity,point,axis,radians)
        inverse = parent_frame.inverse
        pivot = Geom::Point3d.new(point).transform(inverse)
        direction = Geom::Vector3d.new(axis).transform(inverse)
        entity.transform!(Geom::Transformation.rotation(pivot,direction,radians))
      end

      def distance(model,record)
        return Core.number(record.fetch('gap',0)) unless record['r1'] && record['r2']
        low,high = AssemblyMath.interval(plane(model,record['r1']),plane(model,record['r2']))
        high-low
      end

      def self.validate!(records)
        external = records.select { |record| record['external'] }
        proxies = external.map do |record|
          raise Core::Error,'Lặp toàn cụm chưa được hỗ trợ trong liên kết phủ bì cụm.' if record['mode']=='repeat'
          row = Core.copy_data(record)
          AssemblyContainers::REFS.each do |key|
            next unless row[key]
            # Collapse scopes for the external dependency graph. A whole
            # assembly must not indirectly depend on one of its own children.
            row[key] = {'root'=>row[key]['scope'] || row[key]['root']}
          end
          row
        end
        AssemblyMath.ordered(proxies).map { |row| row['id'] }
      end

      def self.resize_assembly(entity)
        model = entity.model
        targets = {}
        changed = AssemblyContainers.normalize_component!(entity,envelopes:targets)
        ScaleRedraw.apply(model,changed.map { |child| ScaleRedraw.prepare(child) }) unless changed.empty?
        records = Assembly.records(model).select { |record| record['scope']==entity.persistent_id.to_s }
        ordered = AssemblyMath.ordered(records)
        Assembly.solve_ordered(model,ordered)
        AssemblyEnvelope.apply(model,targets,ordered)
        ordered.each { |record| Assembly.verify(model,record) }
      end
    end
  end
end
