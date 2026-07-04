# encoding: UTF-8
require 'json'
require 'base64'

module MH
  module AssembleThreeTest
    module ThreeExport
      extend self

      FACE_LIMIT_WARNING = 250_000

      def out_dir
        base = if defined?(MH::Assemble) && MH::Assemble.respond_to?(:out_dir)
                 MH::Assemble.out_dir
               elsif Sketchup.active_model && !Sketchup.active_model.path.to_s.empty?
                 File.join(File.dirname(Sketchup.active_model.path), 'MH_assemble_three_test_out')
               else
                 File.join(ENV['USERPROFILE'] || ENV['HOME'] || '.', 'Desktop', 'MH_assemble_three_test_out')
               end
        Dir.mkdir(base) unless File.directory?(base)
        base
      end

      def export_module(product, mod, profile: 'all')
        ensure_source!
        MH::Assemble.scan_reset if MH::Assemble.respond_to?(:scan_reset)
        label = normalize_module(mod)
        mods = MH::Assemble.scan[product] || {}
        source_parts = (mods[label] || []).reject { |p| p[:flat] }
        return puts("[#{PLUGIN_NAME}] không có part 3D cho #{product}.#{label}") if source_parts.empty?

        all_solids = mods.values.flatten.reject { |p| p[:flat] }
        builders = module_page_builders(product, label, source_parts, resolve_profiles(profile), all_solids, mods)
        run_render_queue(builders, "#{product}.#{label}.three.html", "Three Test #{product}.#{label}")
      end

      def export_product_book(product, profile: 'all')
        ensure_source!
        MH::Assemble.scan_reset if MH::Assemble.respond_to?(:scan_reset)
        builders = product_page_builders(product, profile)
        return notify("Tủ #{product} không có trang để xuất (kiểm tra mã tủ / model).") if builders.empty?
        run_render_queue(builders, "#{product}.three.book.html", "Three Test #{product}")
      end

      def product_pages(product, profile)
        product_page_builders(product, profile).map { |builder| builder.call }.compact
      end

      def notify(msg)
        puts "[#{PLUGIN_NAME}] #{msg}"
        UI.messagebox(msg) rescue nil
        nil
      end

      def export_selection(profile: 'all', product_name: nil)
        selected = Sketchup.active_model.selection.to_a
        selected_ids = {}
        selected.each { |e| selected_ids[e.entityID] = true if e.respond_to?(:entityID) }
        return notify('Chưa chọn gì trong model. Hãy chọn part / module / tủ rồi bấm lại.') if selected_ids.empty?

        parts = []
        if MH::AssembleThreeTest.ensure_assemble
          MH::Assemble.scan_reset if MH::Assemble.respond_to?(:scan_reset)
          MH::Assemble.scan.each do |prod, mods|
            mods.each do |label, arr|
              arr.each do |p|
                ent = p[:entity]
                eid = ent.entityID rescue nil
                in_path = Array(p[:path]).any? { |a| selected_ids[a.entityID] rescue false }
                parts << p.merge(product: prod, module: label) if eid && selected_ids[eid] || in_path
              end
            end
          end
        end

        products = parts.map { |p| p[:product] }.compact.uniq.sort
        unless products.empty?
          save_selection_product_name(products, product_name)
          builders = selection_product_builders(parts, profile)
          return notify("Tủ #{products.join(', ')} không dựng được trang nào (không có part 3D hợp lệ).") if builders.empty?
          filename = products.length == 1 ? "#{products.first}.selection.three.book.html" : 'SELECTION.products.three.book.html'
          title = products.length == 1 ? "Three Test #{products.first} từ selection" : "Three Test Selection #{products.join(', ')}"
          return run_render_queue(builders, filename, title)
        end

        builders = if parts.empty?
                     resolve_profiles(profile).map { |prof| lambda { build_direct_selection_page(selected, prof) } }
                   else
                     resolve_profiles(profile).map do |prof|
                       lambda {
                         visible = visible_parts_for(parts, prof, scope: :module)
                         visible.empty? ? nil : build_page('SELECTION', visible, prof)
                       }
                     end
                   end
        run_render_queue(builders, 'SELECTION.three.html', 'Three Test Selection')
      end

      def save_selection_product_name(products, product_name)
        return unless products.length == 1
        name = product_name.to_s.strip
        return if name.empty?
        @product_name_overrides ||= {}
        @product_name_overrides[products.first.to_s.upcase] = name
        return unless defined?(MH::Assemble) && MH::Assemble.respond_to?(:config) && MH::Assemble.respond_to?(:save_config)

        cfg = MH::Assemble.config
        (cfg['product_names'] ||= {})[products.first.to_s.upcase] = name
        MH::Assemble.save_config
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] Không lưu được tên sản phẩm: #{e.class}: #{e.message}"
      end

      def selection_product_builders(parts, profile)
        profs = resolve_profiles(profile)
        builders = []
        by_product = {}
        parts.each do |part|
          prod = part[:product].to_s
          label = normalize_module(part[:module])
          by_product[prod] ||= {}
          by_product[prod][label] ||= []
          by_product[prod][label] << part
        end

        by_product.keys.sort.each do |product|
          mods = by_product[product]
          all_solids_context = mods.values.flatten.reject { |p| p[:flat] }
          labels = mods.keys.sort

          if labels.size > 1
            profs.each do |prof|
              builders << lambda { build_product_overview_page(product, mods, prof) }
            end
          end

          labels.each do |label|
            source_parts = mods[label].reject { |p| p[:flat] }
            builders.concat(selection_module_page_builders(product, label, source_parts, profs, all_solids_context, mods))
          end
        end
        builders
      end

      def selection_module_page_builders(product, label, source_parts, profs, all_solids_context, mods)
        builders = []
        mini_ref = []
        module_profiles(source_parts, profs, scope: :module).each do |prof|
          builders << lambda {
            mini_ref[0] ||= build_minimap(product, label, all_solids_context, mods, base_parts: all_solids_context, highlight: source_parts)
            parts = visible_parts_for(source_parts, prof, scope: :module)
            next nil if parts.empty?
            split = split_sub_modules(parts)
            code = mods.keys.sort == ['00'] ? product : "#{product}.#{label}"
            build_page(code, parts, prof, mini: mini_ref[0], sub_split: split)
          }
        end

        module_profiles(source_parts, profs, scope: :module).each do |prof|
          parts = visible_parts_for(source_parts, prof, scope: :module)
          split = split_sub_modules(parts)
          split[:clusters].each do |cluster|
            next if prof.to_s == 'no_door' && !no_door_applies_to_parts?(cluster[:parts], :module)

            builders << lambda {
              build_sub_module_page(product, label, cluster, prof, mods, parts)
            }
          end
        end
        builders
      end

      def resolve_profiles(profile)
        list = if profile.nil? || profile.to_s.strip.empty? || profile.to_s == 'all'
                 %w[full no_door]
               else
                 [profile.to_s]
               end
        if defined?(MH::Assemble) && MH::Assemble.respond_to?(:profiles)
          list.select { |p| MH::Assemble.profiles.key?(p) }
        else
          list
        end
      end

      def module_profiles(parts, profs, scope: :module)
        return profs unless profs.include?('no_door')

        no_door_applies_to_parts?(parts, scope) ? profs : (profs - ['no_door'])
      end

      def no_door_applies_to_parts?(parts, scope)
        return false unless defined?(MH::Assemble) && MH::Assemble.respond_to?(:no_door_scope)

        scope_key = scope.to_s == 'product' ? 'product' : 'module'
        names = Array(MH::Assemble.no_door_scope[scope_key]).map { |name| norm_part_name(name) }.reject(&:empty?)
        return false if names.empty?

        Array(parts).any? do |part|
          names.include?(norm_part_name(part[:part])) ||
            Array(part[:path]).any? { |ancestor| no_door_ancestor_match?(ancestor, names) }
        end
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] kiểm tra no_door lỗi: #{e.class}: #{e.message}"
        false
      end

      def no_door_ancestor_match?(entity, names)
        return false unless entity && entity.respond_to?(:name)

        nm = entity.name.to_s
        parsed = if defined?(MH::ProductContext) && MH::ProductContext.respond_to?(:parse_full)
                   MH::ProductContext.parse_full(nm)
                 end
        names.include?(norm_part_name(parsed ? parsed[:part] : nm))
      rescue StandardError
        false
      end

      def norm_part_name(text)
        text.to_s.strip.downcase.gsub(/\s+/, '')
      end

      def visible_parts_for(parts, profile, scope: :module)
        visible = if MH::Assemble.respond_to?(:visible_parts_scoped)
                    MH::Assemble.visible_parts_scoped(parts, profile, scope)
                  elsif MH::Assemble.respond_to?(:visible_parts)
                    MH::Assemble.visible_parts(parts, profile)
                  else
                    parts
                  end
        visible.reject { |part| part_hidden_by_tag?(part) }
      end

      def part_numbered?(part)
        return false unless part[:numbered]
        return false if defined?(MH::Assemble) && MH::Assemble.respond_to?(:no_number?) && MH::Assemble.no_number?(part[:part])

        true
      end

      def part_hidden_by_tag?(part)
        ent = part[:entity]
        hidden_tag_entity?(ent) || Array(part[:path]).any? { |ancestor| hidden_tag_entity?(ancestor) }
      end

      def hidden_tag_entity?(entity)
        tag = entity_tag_name(entity)
        return false if tag.empty?

        hidden_tag_names.include?(norm_part_name(tag))
      end

      def hidden_tag_names
        if defined?(MH::Assemble) && MH::Assemble.respond_to?(:hidden_tags)
          MH::Assemble.hidden_tags.map { |name| norm_part_name(name) }.reject(&:empty?)
        else
          []
        end
      end

      def entity_tag_name(entity)
        return '' unless entity
        layer = if entity.respond_to?(:layer)
                  entity.layer
                elsif entity.respond_to?(:tag)
                  entity.tag
                end
        layer && layer.respond_to?(:name) ? layer.name.to_s : ''
      rescue StandardError
        ''
      end

      def ensure_source!
        ok = MH::AssembleThreeTest.ensure_assemble
        raise 'Không load được MH_assemble để lấy scan/part.' unless ok
      end

      def normalize_module(mod)
        s = mod.to_s.strip
        s =~ /\A\d+\z/ ? format('%02d', s.to_i) : s
      end

      # Khung tên: lấy Tên công trình + Tên sản phẩm từ MH::Assemble (ghép MH_shared/MH_Thongke),
      # giống app MH_assemble gốc. product_base = mã SP (vd "SP47") suy từ code.
      def title_block_for(code)
        base = code.to_s.split('.').first.to_s
        project = ''
        product = ''
        begin
          project = MH::Assemble.project_title.to_s if defined?(MH::Assemble) && MH::Assemble.respond_to?(:project_title)
        rescue StandardError
          project = ''
        end
        begin
          override = (@product_name_overrides || {})[base.to_s.upcase]
          product = override.to_s if override && !override.to_s.empty?
          product = MH::Assemble.product_name(base).to_s if product.empty? && base =~ /\A[A-Za-z]/ && defined?(MH::Assemble) && MH::Assemble.respond_to?(:product_name)
        rescue StandardError
          product = ''
        end
        { 'project' => project, 'product' => product, 'code' => code.to_s }
      end

      def build_page(code, parts, profile, mini: nil, sub_split: nil, table_caption: 'Danh sách tấm')
        started = Time.now
        meshes = []
        table_rows = []
        extra_labels = []
        cluster_part_ids = {}
        bounds = Bounds.new
        face_count = 0
        if sub_split
          Array(sub_split[:clusters]).each do |cluster|
            Array(cluster[:parts]).each { |part| cluster_part_ids[part.object_id] = cluster }
            extra_labels << { id: cluster[:code], point: cluster[:bounds].center }
          end
        end
        parts.each do |part|
          mesh = mesh_for_part(part)
          next if mesh[:vertices].empty? && mesh[:edges].empty? && mesh[:guides].empty?
          cluster = cluster_part_ids[part.object_id]
          mesh[:id] = part[:id] || (meshes.length + 1)
          mesh[:name] = part[:part]
          mesh[:material] = part[:material]
          numbered = part_numbered?(part)
          mesh[:pin] = false if cluster || !numbered
          meshes << mesh
          table_rows << { id: mesh[:id], name: mesh[:name], material: mesh[:material] } if numbered && !cluster
          mesh[:vertices].each_slice(3) { |x, y, z| bounds.add(x, y, z) }
          mesh[:edges].each_slice(3) { |x, y, z| bounds.add(x, y, z) }
          mesh[:guides].each_slice(3) { |x, y, z| bounds.add(x, y, z) }
          face_count += mesh[:vertices].length / 9
        end
        if sub_split
          Array(sub_split[:clusters]).each do |cluster|
            table_rows << { id: cluster[:code], name: "#{cluster[:label]} (#{cluster[:parts].size} tấm)", material: '' }
          end
        end
        warn = face_count > FACE_LIMIT_WARNING ? "Model nhiều mặt: #{face_count} tam giác, HTML có thể mở chậm." : nil
        {
          code: code,
          profile: profile,
          generated_at: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
          duration_ms: ((Time.now - started) * 1000).round,
          face_count: face_count,
          warning: warn,
          bounds: bounds.to_h,
          mini: mini,
          overview: false,
          table_caption: table_caption,
          table_rows: table_rows,
          extra_labels: extra_labels,
          title: title_block_for(code),
          meshes: meshes
        }
      end

      def build_product_overview_page(product, mods, profile)
        started = Time.now
        meshes = []
        labels = []
        table_rows = []
        bounds = Bounds.new
        face_count = 0

        mods.keys.sort.each do |label|
          parts = visible_parts_for(mods[label].reject { |p| p[:flat] }, profile, scope: :product)
          next if parts.empty?

          module_bounds = Bounds.new
          module_has_mesh = false
          parts.each do |part|
            mesh = mesh_for_part(part)
            next if mesh[:vertices].empty? && mesh[:edges].empty? && mesh[:guides].empty?

            mesh[:id] = part[:id] || (meshes.length + 1)
            mesh[:name] = part[:part]
            mesh[:material] = part[:material]
            mesh[:edges] = triangle_edges(mesh[:vertices]) if mesh[:edges].empty?
            mesh[:pin] = false unless part_numbered?(part)
            meshes << mesh
            mesh[:vertices].each_slice(3) do |x, y, z|
              bounds.add(x, y, z)
              module_bounds.add(x, y, z)
            end
            mesh[:edges].each_slice(3) do |x, y, z|
              bounds.add(x, y, z)
              module_bounds.add(x, y, z)
            end
            mesh[:guides].each_slice(3) do |x, y, z|
              bounds.add(x, y, z)
              module_bounds.add(x, y, z)
            end
            face_count += mesh[:vertices].length / 9
            module_has_mesh = true
          end
          next unless module_has_mesh

          labels << { id: label.to_i, point: module_bounds.center }
          listed_count = if MH::Assemble.respond_to?(:listed_parts)
                           MH::Assemble.listed_parts(parts, profile).size
                         else
                           parts.size
                         end
          table_rows << { id: label.to_i, name: "Module #{label}", qty: listed_count, material: '' }
        end

        return nil if meshes.empty?
        warn = face_count > FACE_LIMIT_WARNING ? "Model nhiều mặt: #{face_count} tam giác, HTML có thể mở chậm." : nil
        {
          code: product,
          profile: profile,
          generated_at: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
          duration_ms: ((Time.now - started) * 1000).round,
          face_count: face_count,
          warning: warn,
          bounds: bounds.to_h,
          mini: nil,
          overview: true,
          table_caption: "Tủ #{product} - #{table_rows.size} module",
          table_rows: table_rows,
          labels: labels,
          title: title_block_for(product),
          meshes: meshes
        }
      end

      def sub_module_rules
        return [] unless defined?(MH::Assemble) && MH::Assemble.respond_to?(:sub_modules)
        MH::Assemble.sub_modules.each_with_index.map do |row, index|
          next unless row.is_a?(Hash)
          next if row.key?('enabled') && !row['enabled']
          key = row['key'].to_s.strip
          label = row['label'].to_s.strip
          next if key.empty? || label.empty?
          { key: key, label: label, norm: norm_sub_key(key), order: index }
        end.compact.sort_by { |rule| [-rule[:norm].length, rule[:order]] }
      end

      def norm_sub_key(text)
        text.to_s.downcase.gsub(/[\s_\-]+/, '')
      end

      def sub_rule_for(part, rules)
        name = norm_sub_key(part[:part])
        rules.find { |rule| name.start_with?(rule[:norm]) }
      end

      def split_sub_modules(parts)
        rules = sub_module_rules
        return { main: parts, clusters: [] } if rules.empty?

        main = []
        grouped = {}
        parts.each do |part|
          rule = sub_rule_for(part, rules)
          unless rule
            main << part
            next
          end
          container = sub_container_key(part)
          key = [rule[:order], container]
          grouped[key] ||= { rule: rule, parts: [], container: container }
          grouped[key][:parts] << part
        end

        clusters = []
        grouped.values.each do |data|
          groups = data[:container] == :loose ? spatial_part_groups(data[:parts]) : [data[:parts]]
          groups.each do |group_parts|
            if group_parts.size < 2
              main.concat(group_parts)
              next
            end
            bounds = bounds_for_parts(group_parts)
            clusters << data.merge(parts: group_parts, bounds: bounds)
          end
        end

        counters = Hash.new(0)
        clusters.sort_by! { |c| center = c[:bounds].center; [-center[2], center[0], center[1], c[:rule][:order]] }
        clusters.each do |cluster|
          short = short_code(cluster[:rule][:label], cluster[:rule][:key])
          counters[short] += 1
          cluster[:key] = cluster[:rule][:key]
          cluster[:label] = cluster[:rule][:label]
          cluster[:short] = short
          cluster[:idx] = counters[short]
          cluster[:code] = "#{short}#{cluster[:idx]}"
        end

        { main: main, clusters: clusters }
      end

      def sub_container_key(part)
        path = Array(part[:path]).select { |entity| entity && (entity.valid? rescue true) }
        return :loose if path.empty?
        entity = path.last
        entity.respond_to?(:entityID) ? entity.entityID : entity.object_id
      rescue StandardError
        :loose
      end

      def spatial_part_groups(parts)
        items = Array(parts).map { |part| { part: part, bounds: bounds_for_parts([part]).to_h } }
        return [] if items.empty?

        groups = []
        items.each do |item|
          attached = groups.select { |group| group[:items].any? { |other| bounds_touch?(item[:bounds], other[:bounds]) } }
          if attached.empty?
            groups << { items: [item] }
            next
          end
          base = attached.shift
          base[:items] << item
          attached.each do |group|
            base[:items].concat(group[:items])
            groups.delete(group)
          end
        end
        groups.map { |group| group[:items].map { |item| item[:part] } }
      end

      def bounds_touch?(a, b, tolerance = 0.35)
        3.times.all? do |i|
          a[:min][i].to_f <= b[:max][i].to_f + tolerance &&
            b[:min][i].to_f <= a[:max][i].to_f + tolerance
        end
      end

      def short_code(label, fallback)
        words = label.to_s.strip.split(/\s+/)
        short = words.map { |word| word[0] }.join.upcase
        short = fallback.to_s.strip[0, 2].to_s.upcase if short.empty?
        short.gsub(/[^0-9A-ZÀ-Ỵ]/i, '')
      end

      def bounds_for_parts(parts)
        bounds = Bounds.new
        parts.each do |part|
          mesh = mesh_for_part(part)
          mesh[:vertices].each_slice(3) { |x, y, z| bounds.add(x, y, z) }
          mesh[:edges].each_slice(3) { |x, y, z| bounds.add(x, y, z) }
          mesh[:guides].each_slice(3) { |x, y, z| bounds.add(x, y, z) }
        end
        bounds
      end

      def build_sub_module_page(product, label, cluster, prof, mods, module_solids)
        mini = build_minimap(product, label, module_solids, mods,
                             highlight: cluster[:parts],
                             base_parts: module_solids,
                             over_tag: "#{label}.#{cluster[:code]}.#{prof}",
                             base_tag: "m#{label}")
        build_page("#{product}.#{label}.#{cluster[:code]}", cluster[:parts], prof,
                   mini: mini,
                   table_caption: "#{cluster[:label]} #{cluster[:idx]} - danh sách tấm")
      end

      def build_minimap(product, label, all_solids, mods, **options)
        return nil unless defined?(MH::Assemble) && MH::Assemble.respond_to?(:render_minimap_module)
        mini = MH::Assemble.render_minimap_module(product, label, all_solids, mods, **options)
        return nil unless mini && mini['base']
        {
          'base' => mini['base'],
          'overlay' => mini['overlay']
        }
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] không tạo được mini-map #{product}.#{label}: #{e.class}: #{e.message}"
        nil
      end

      def build_direct_selection_pages(selected, profile)
        resolve_profiles(profile).map do |prof|
          build_direct_selection_page(selected, prof)
        end.compact
      end

      def build_direct_selection_page(selected, profile)
        started = Time.now
        meshes = []
        bounds = Bounds.new
        face_count = 0

        selected.each_with_index do |entity, index|
          mesh = mesh_for_entity(entity, Geom::Transformation.new)
          next if mesh[:vertices].empty? && mesh[:guides].empty?
          mesh[:id] = index + 1
          mesh[:name] = entity_name(entity)
          mesh[:material] = ''
          meshes << mesh
          mesh[:vertices].each_slice(3) { |x, y, z| bounds.add(x, y, z) }
          mesh[:guides].each_slice(3) { |x, y, z| bounds.add(x, y, z) }
          face_count += mesh[:vertices].length / 9
        end

        return nil if meshes.empty?
        warn = face_count > FACE_LIMIT_WARNING ? "Model nhiều mặt: #{face_count} tam giác, HTML có thể mở chậm." : nil
        {
          code: 'SELECTION',
          profile: profile,
          generated_at: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
          duration_ms: ((Time.now - started) * 1000).round,
          face_count: face_count,
          warning: warn,
          bounds: bounds.to_h,
          mini: nil,
          title: title_block_for('SELECTION'),
          meshes: meshes
        }
      end

      def mesh_for_part(part)
        ent = part[:entity]
        return { vertices: [], edges: [], guides: [], color: 0xdddddd } if part_hidden_by_tag?(part)

        tr = part[:tr] || Geom::Transformation.new
        vertices = []
        edges = []
        guides = []
        color = color_for_entity(ent)

        if ent.is_a?(Sketchup::Group)
          collect_entities(ent.entities, tr * ent.transformation, vertices, edges, guides, color)
        elsif ent.is_a?(Sketchup::ComponentInstance)
          collect_entities(ent.definition.entities, tr * ent.transformation, vertices, edges, guides, color)
        end

        { vertices: vertices, edges: edges, guides: guides, color: color }
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] bỏ qua part #{part[:raw]}: #{e.class}: #{e.message}"
        { vertices: [], edges: [], guides: [], color: 0xdddddd }
      end

      def mesh_for_entity(entity, parent_tr)
        return { vertices: [], edges: [], guides: [], color: 0xdddddd } if hidden_tag_entity?(entity)

        vertices = []
        edges = []
        guides = []
        color = color_for_entity(entity)

        if entity.is_a?(Sketchup::Group)
          collect_entities(entity.entities, parent_tr * entity.transformation, vertices, edges, guides, color)
        elsif entity.is_a?(Sketchup::ComponentInstance)
          collect_entities(entity.definition.entities, parent_tr * entity.transformation, vertices, edges, guides, color)
        elsif entity.is_a?(Sketchup::Face)
          collect_entities([entity], parent_tr, vertices, edges, guides, color)
        elsif entity.is_a?(Sketchup::Edge) || entity.is_a?(Sketchup::ConstructionLine) || entity.is_a?(Sketchup::ConstructionPoint)
          collect_entities([entity], parent_tr, vertices, edges, guides, color)
        end

        { vertices: vertices, edges: edges, guides: guides, color: color }
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] bỏ qua selection #{entity}: #{e.class}: #{e.message}"
        { vertices: [], edges: [], guides: [], color: 0xdddddd }
      end

      def collect_entities(entities, tr, vertices, edges, guides, inherited_color)
        entities.each do |e|
          next if e.respond_to?(:visible?) && !e.visible?
          next if e.respond_to?(:hidden?) && e.hidden?
          next if hidden_tag_entity?(e)

          if e.is_a?(Sketchup::Face)
            mesh = e.mesh(0)
            pts = mesh.points.map { |p| p.transform(tr) }
            mesh.polygons.each do |poly|
              ids = poly.map { |idx| idx.abs - 1 }
              next if ids.length < 3
              (1...(ids.length - 1)).each do |i|
                [ids[0], ids[i], ids[i + 1]].each do |idx|
                  p = pts[idx]
                  vertices << p.x.to_f << p.y.to_f << p.z.to_f
                end
              end
            end
          elsif e.is_a?(Sketchup::Edge)
            e.vertices.each do |v|
              p = v.position.transform(tr)
              edges << p.x.to_f << p.y.to_f << p.z.to_f
            end
          elsif e.is_a?(Sketchup::ConstructionLine)
            append_construction_line(e, tr, guides)
          elsif e.is_a?(Sketchup::ConstructionPoint)
            append_construction_point(e, tr, guides)
          elsif e.is_a?(Sketchup::Group)
            collect_entities(e.entities, tr * e.transformation, vertices, edges, guides, color_for_entity(e) || inherited_color)
          elsif e.is_a?(Sketchup::ComponentInstance)
            collect_entities(e.definition.entities, tr * e.transformation, vertices, edges, guides, color_for_entity(e) || inherited_color)
          end
        end
      end

      def append_construction_line(entity, tr, guides)
        if entity.respond_to?(:start) && entity.respond_to?(:end) && entity.start && entity.end
          p1 = entity.start.transform(tr)
          p2 = entity.end.transform(tr)
        else
          origin = if entity.respond_to?(:position)
                     entity.position
                   elsif entity.respond_to?(:line)
                     entity.line[0]
                   end
          direction = if entity.respond_to?(:direction)
                        entity.direction
                      elsif entity.respond_to?(:line)
                        entity.line[1]
                      end
          return unless origin && direction
          dir = direction.clone
          return if dir.length <= 0.0
          dir.length = 80.0
          rev = dir.clone
          rev.reverse!
          p1 = origin.offset(rev).transform(tr)
          p2 = origin.offset(dir).transform(tr)
        end
        guides << p1.x.to_f << p1.y.to_f << p1.z.to_f << p2.x.to_f << p2.y.to_f << p2.z.to_f
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] bỏ qua guide line: #{e.class}: #{e.message}"
      end

      def append_construction_point(entity, tr, guides)
        return unless entity.respond_to?(:position)
        p = entity.position.transform(tr)
        size = 1.25
        [[-size, 0, 0, size, 0, 0], [0, -size, 0, 0, size, 0], [0, 0, -size, 0, 0, size]].each do |x1, y1, z1, x2, y2, z2|
          guides << p.x + x1 << p.y + y1 << p.z + z1 << p.x + x2 << p.y + y2 << p.z + z2
        end
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] bỏ qua guide point: #{e.class}: #{e.message}"
      end

      def color_for_entity(entity)
        mat = entity.respond_to?(:material) ? entity.material : nil
        mat = entity.definition.material if mat.nil? && entity.respond_to?(:definition) && entity.definition.respond_to?(:material)
        return 0xd8d8d8 unless mat && mat.respond_to?(:color)
        (mat.color.red << 16) + (mat.color.green << 8) + mat.color.blue
      rescue StandardError
        0xd8d8d8
      end

      def entity_name(entity)
        name = entity.respond_to?(:name) ? entity.name.to_s : ''
        if name.strip.empty? && entity.respond_to?(:definition) && entity.definition
          name = entity.definition.name.to_s
        end
        name.strip.empty? ? entity.class.name.split('::').last : name
      rescue StandardError
        'Object'
      end

      # Đẩy tiến độ ra dashboard (nếu đang mở) + status bar.
      def report_progress(done, total, text)
        pct = total > 0 ? (done * 100 / total) : 100
        Sketchup.status_text = "#{PLUGIN_NAME} #{done}/#{total} (#{pct}%): #{text}"
        panel = (MH::AssembleThreeTest.respond_to?(:panel) ? MH::AssembleThreeTest.panel : nil) rescue nil
        return unless panel
        begin
          panel.execute_script("mhThreeProgress(#{pct}, #{done}, #{total}, #{text.to_json})")
        rescue StandardError
          nil
        end
      end

      # builders = mảng lambda, mỗi cái trả 1 page hash (hoặc nil). Render theo NHỊP timer để
      # dashboard kịp cập nhật % và SketchUp không bị treo. Cuối cùng ghi file + mở browser.
      def run_render_queue(builders, filename, title)
        builders = Array(builders)
        return notify('Không có trang để xuất.') if builders.empty?
        pages = []
        total = builders.size
        i = 0
        report_progress(0, total, 'Bắt đầu render...')
        step = nil
        step = lambda {
          if i >= total
            good = pages.compact
            if good.empty?
              report_progress(total, total, 'Không dựng được trang')
              notify('Không dựng được trang nào (không có part 3D hợp lệ).')
            else
              write_book(good, filename, title)
              report_progress(total, total, "Xong -> #{filename}")
            end
            next
          end
          begin
            pages << builders[i].call
          rescue StandardError => e
            puts "[#{PLUGIN_NAME}] render trang #{i + 1} lỗi: #{e.class}: #{e.message}"
          end
          i += 1
          report_progress(i, total, "Render trang #{i}/#{total}")
          UI.start_timer(0.01, false) { step.call }
        }
        UI.start_timer(0.01, false) { step.call }
        nil
      end

      # Như product_pages nhưng trả về MẢNG LAMBDA (mỗi lambda dựng 1 trang) để render có tiến độ.
      def product_page_builders(product, profile)
        mods = MH::Assemble.scan[product]
        return [] unless mods
        builders = []
        all_solids_context = mods.values.flatten.reject { |p| p[:flat] }
        profs = resolve_profiles(profile)
        labels = mods.keys.sort
        if labels == ['00']
          source_parts = mods['00'].reject { |p| p[:flat] }
          module_profiles(source_parts, profs, scope: :module).each do |prof|
            builders << lambda {
              parts = visible_parts_for(source_parts, prof, scope: :module)
              next nil if parts.empty?
              split = split_sub_modules(parts)
              build_page(product, parts, prof, sub_split: split)
            }
          end
          module_profiles(source_parts, profs, scope: :module).each do |prof|
            parts = visible_parts_for(source_parts, prof, scope: :module)
            split = split_sub_modules(parts)
            split[:clusters].each do |cluster|
              next if prof.to_s == 'no_door' && !no_door_applies_to_parts?(cluster[:parts], :module)

              builders << lambda { build_sub_module_page(product, '00', cluster, prof, mods, parts) }
            end
          end
          return builders
        end
        profs.each do |prof|
          builders << lambda { build_product_overview_page(product, mods, prof) }
        end
        labels.each do |label|
          source_parts = mods[label].reject { |p| p[:flat] }
          builders.concat(module_page_builders(product, label, source_parts, profs, all_solids_context, mods))
        end
        builders
      end

      def module_page_builders(product, label, source_parts, profs, all_solids_context, mods)
        builders = []
        mini_ref = []
        module_profiles(source_parts, profs, scope: :module).each do |prof|
          builders << lambda {
            mini_ref[0] ||= build_minimap(product, label, all_solids_context, mods)
            parts = visible_parts_for(source_parts, prof, scope: :module)
            next nil if parts.empty?
            split = split_sub_modules(parts)
            build_page("#{product}.#{label}", parts, prof, mini: mini_ref[0], sub_split: split)
          }
        end

        # Trang con tính theo profile sau lọc: cluster không đủ part ở profile đó sẽ tự biến mất.
        module_profiles(source_parts, profs, scope: :module).each do |prof|
          parts = visible_parts_for(source_parts, prof, scope: :module)
          split = split_sub_modules(parts)
          split[:clusters].each do |cluster|
            next if prof.to_s == 'no_door' && !no_door_applies_to_parts?(cluster[:parts], :module)

            builders << lambda {
              build_sub_module_page(product, label, cluster, prof, mods, visible_parts_for(source_parts, prof, scope: :module))
            }
          end
        end
        builders
      end

      def write_book(pages, filename, title)
        path = File.join(out_dir, filename)
        File.write(path, html_for(pages, title))
        total_faces = pages.map { |p| p[:face_count].to_i }.inject(0, :+)
        puts "[#{PLUGIN_NAME}] xuất #{pages.size} trang / #{total_faces} tam giác -> #{path}"
        Sketchup.status_text = "#{PLUGIN_NAME}: Đã xuất #{pages.size} trang -> #{path}"
        url = file_url(path)
        UI.start_timer(0.2, false) { open_export_file(path, url) }
        path
      end

      def file_url(path)
        "file:///#{encode_url_path(path.tr('\\', '/'))}"
      end

      def open_export_file(path, url = file_url(path))
        if Sketchup.platform == :platform_win
          # Mở thẳng FILE bằng đường dẫn Windows (verb 'open' -> trình duyệt mặc định cho .html).
          # KHÔNG dùng rundll32+FileProtocolHandler với url đã %-encode: ShellExecute không báo lỗi
          # nhưng cũng KHÔNG mở được -> tưởng chạy xong mà browser im.
          native = File.expand_path(path).tr('/', '\\')
          begin
            require 'win32ole'
            WIN32OLE.new('Shell.Application').ShellExecute(native, '', '', 'open', 1)
            return true
          rescue StandardError => e
            puts "[#{PLUGIN_NAME}] ShellExecute lỗi: #{e.class}: #{e.message}"
          end
        end

        UI.openURL(url)
        true
      rescue StandardError => e
        puts "[#{PLUGIN_NAME}] không mở được browser: #{e.class}: #{e.message}"
        UI.openURL(url) rescue false
        false
      end

      def triangle_edges(vertices)
        edges = []
        vertices.each_slice(9) do |x1, y1, z1, x2, y2, z2, x3, y3, z3|
          edges.concat([x1, y1, z1, x2, y2, z2, x2, y2, z2, x3, y3, z3, x3, y3, z3, x1, y1, z1])
        end
        edges
      end

      def encode_url_path(path)
        path.encode('UTF-8').bytes.map do |byte|
          char = byte.chr
          if char =~ /[A-Za-z0-9_.~\/:-]/
            char
          else
            format('%%%02X', byte)
          end
        end.join
      end

      def html_for(pages, title)
        data = JSON.generate(pages)
        three_path = File.join(Sketchup.find_support_file('Plugins'), 'ladb_opencutlist', 'js', 'lib', 'three.min.js').tr('\\', '/')
        controls_path = File.join(Sketchup.find_support_file('Plugins'), 'ladb_opencutlist', 'js', 'lib', 'three-orbit-controls.min.js').tr('\\', '/')
        default_ratio = if defined?(MH::Assemble) && MH::Assemble.respond_to?(:draw_ratio)
                          MH::Assemble.draw_ratio.to_s
                        else
                          'auto'
                        end
        ratio_presets = if defined?(MH::Assemble) && MH::Assemble.respond_to?(:draw_ratios)
                          MH::Assemble.draw_ratios
                        else
                          [5, 10, 15, 20, 25, 50, 100]
                        end
        ratio_presets = [5, 10, 15, 20, 25, 50, 100] if ratio_presets.empty?
        ratio_presets = ratio_presets.map(&:to_i).select { |n| n.between?(1, 1000) }.uniq
        custom_ratio = (default_ratio == 'auto' || ratio_presets.map(&:to_s).include?(default_ratio)) ? '' : default_ratio.to_i.to_s
        ratio_active = lambda { |value| default_ratio == value.to_s ? ' class="active"' : '' }
        ratio_rows_html = ([['auto'] + ratio_presets.map(&:to_s)].flatten).each_slice(2).map do |pair|
          buttons = pair.map do |value|
            label = value == 'auto' ? 'AUTO' : value
            title = value == 'auto' ? 'Tự chọn tỉ lệ chuẩn vừa khung' : "1:#{value}"
            %(<button data-ratio="#{value}"#{ratio_active.call(value)} title="#{escape_html(title)}">#{escape_html(label)}</button>)
          end.join
          %('<div class="row">#{buttons}</div>' +)
        end.join("\n                          ")
        scale_steps = ratio_presets.sort
        <<~HTML
          <!doctype html>
          <html>
          <head>
            <meta charset="utf-8">
            <title>#{escape_html(title)}</title>
            <style>
              @page { size: A3 landscape; margin: 0; }
              * { box-sizing: border-box; }
              body { margin:0; background:#ddd; font-family:Arial,sans-serif; -webkit-print-color-adjust:exact; print-color-adjust:exact; }
              .toolbar { position:fixed; right:12px; top:12px; z-index:10; background:#222; color:white; padding:10px; border-radius:6px; width:170px; }
              .toolbar button { width:100%; margin-top:6px; padding:6px; }
              .page { width:420mm; height:297mm; background:white; margin:12px auto; padding:10mm; page-break-after:always; }
              .sheet { width:100%; height:100%; border:2px solid #000; display:flex; flex-direction:column; }
              .head { height:16mm; border-bottom:1px solid #000; display:flex; align-items:center; padding:0 8mm; gap:12mm; }
              .head b { font-size:16pt; }
              .body { flex:1; min-height:0; display:flex; position:relative; }
              .viewbox { flex:1; min-width:0; position:relative; overflow:hidden; }
              .viewer { width:100%; height:100%; }
              .viewer .print-snapshot { width:100%; height:100%; object-fit:contain; display:none; }
              .leaders { position:absolute; inset:0; width:100%; height:100%; pointer-events:none; overflow:hidden; z-index:2; }
              .pins { position:absolute; inset:0; pointer-events:none; overflow:hidden; z-index:3; }
              .pin { position:absolute; min-width:20px; height:20px; padding:0 5px; border:1px solid #111; border-radius:10px;
                     background:#fff; color:#000; font:bold 10pt/18px Arial,sans-serif; text-align:center;
                     transform:translate(-50%,-50%); box-shadow:0 1px 2px rgba(0,0,0,.18); z-index:4; }
              .pin.hidden { display:none; }
              .view-ui-left { position:absolute; left:8px; top:8px; z-index:5; display:flex; flex-direction:column; gap:4px; }
              .view-ui-left .row { display:flex; gap:4px; }
              .view-ui-left button { width:34px; height:26px; border:1px solid #888; background:#fff; font:bold 9px Arial; padding:0; }
              .view-ui-left button.active { background:#222; color:#fff; }
              .view-ui-left .ratio-custom { display:flex; align-items:center; gap:2px; background:#fff; border:1px solid #888; padding:2px; font:bold 9px Arial; }
              .view-ui-left .ratio-custom input { width:38px; height:20px; border:0; border-left:1px solid #aaa; font:bold 9px Arial; padding:1px 2px; }
              .view-ui-right { position:absolute; right:8px; top:8px; bottom:8px; z-index:5; display:flex; flex-direction:column; align-items:center; gap:8px; }
              .vcontrol { display:flex; align-items:center; gap:5px; background:rgba(255,255,255,.92); border:1px solid #888; padding:5px 3px; }
              .vcontrol input { writing-mode:bt-lr; -webkit-appearance:slider-vertical; width:24px; height:120px; }
              .vcontrol span { writing-mode:vertical-rl; transform:rotate(180deg); font:bold 9px Arial; }
              .checkcontrol { display:flex; flex-direction:column; gap:4px; background:rgba(255,255,255,.92); border:1px solid #888; padding:5px; font:bold 9px Arial; }
              .checkcontrol label { display:flex; gap:4px; align-items:center; white-space:nowrap; }
              .right { width:104mm; border-left:1px solid #000; display:flex; flex-direction:column; min-height:0; }
              .mini { height:82mm; border-bottom:1px solid #000; position:relative; background:#fff; display:flex; align-items:center; justify-content:center; overflow:hidden; }
              .mini .mini-stack { position:relative; width:100%; height:100%; }
              .mini img { max-width:100%; max-height:100%; object-fit:contain; }
              .mini .mini-overlay { position:absolute; inset:0; width:100%; height:100%; object-fit:contain; }
              .mini .mini-base { position:absolute; inset:0; width:100%; height:100%; object-fit:contain; mix-blend-mode:multiply; }
              .mini-empty { color:#777; font-size:9pt; }
              .caption { font-weight:bold; padding:5px 7px; border-bottom:1px solid #000; background:#eee; font-size:10pt; }
              .tablewrap { flex:1; overflow:hidden; }
              table { width:100%; border-collapse:collapse; font-size:8pt; table-layout:fixed; }
              th,td { border:1px solid #555; padding:2px 4px; text-align:left; vertical-align:top; overflow-wrap:break-word; word-break:break-word; }
              td.mat { word-break:break-all; }   /* mã VL dài kiểu HDFCA.17.AC.MS.446FR -> bẻ dòng được */
              th { background:#f3f3f3; }
              td.c, th.c { text-align:center; }
              .title { height:13mm; border-top:2px solid #000; display:flex; }
              .title .cell { flex:1; border-right:1px solid #000; padding:1px 8px; display:flex; flex-direction:column; justify-content:center; }
              .title .cell:last-child { border-right:none; }
              .title .lb { font-size:7.5pt; color:#555; }
              .title .vl { font-size:11pt; font-weight:bold; line-height:1.1; }
              .warn { color:#a30; font-weight:bold; }
              @media print {
                body { background:white; }
                .toolbar, .no-print { display:none !important; }
                .page { margin:0; }
                .viewbox { overflow:hidden !important; }
                .viewer canvas { display:none !important; }
                .viewer .print-snapshot { display:block !important; }
              }
            </style>
          </head>
          <body>
            <div class="toolbar">
              <b>Three Test</b>
              <label style="display:flex;gap:6px;align-items:center;margin-top:8px;font-size:12px"><input type="checkbox" id="allMono"> Không màu (tất cả)</label>
              <label style="display:flex;gap:6px;align-items:center;font-size:12px"><input type="checkbox" id="allBack"> Back edge (tất cả)</label>
              <button id="printBtn">In PDF</button>
            </div>
            <div id="pages"></div>
            <script src="file:///#{three_path}"></script>
            <script src="file:///#{controls_path}"></script>
            <script>
              const PAGES = #{data};
              // Đỉnh hình học tính bằng INCH (SketchUp internal). Quy đổi sang mm để ra TỈ LỆ KỸ THUẬT thật.
              const INCH_MM = 25.4;
              // Kích thước VÙNG VẼ trên giấy A3 (mm), suy từ layout (page 420x297, padding 10, đầu 16, khung tên 13, cột phải 104).
              const PAPER_VIEW_H_MM = 246.0;
              const PAPER_VIEW_W_MM = 294.5;
              const SCALE_STEPS = #{JSON.generate(scale_steps)};
              const root = document.getElementById('pages');
              const printBtn = document.getElementById('printBtn');
              let printPrepared = false;
              if (printBtn) printBtn.addEventListener('click', preparePrint);
              window.addEventListener('beforeprint', function() {
                if (!printPrepared) freezeAllForPrint();
              });
              window.addEventListener('afterprint', function() {
                printPrepared = false;
                lazyViewers.forEach(function(item) {
                  if (item.visible) initLazyItem(item);
                });
              });

              function makePage(page, index) {
                const el = document.createElement('div');
                el.className = 'page';
                el.innerHTML =
                  '<div class="sheet">' +
                    '<div class="head"><b>' + esc(displayCode(page)) + '</b></div>' +
                    '<div class="body">' +
                      '<div class="viewbox">' +
                        '<div class="viewer"></div><svg class="leaders"></svg><div class="pins"></div>' +
                        '<div class="view-ui-left no-print">' +
                          '<div class="row"><button data-view="iso_fr" title="Iso trước phải">I-FR</button><button data-view="iso_fl" title="Iso trước trái">I-FL</button></div>' +
                          '<div class="row"><button data-view="iso_br" title="Iso sau phải">I-BR</button><button data-view="iso_bl" title="Iso sau trái">I-BL</button></div>' +
                          '<button data-view="top" title="Top">TOP</button>' +
                          '<button data-view="bottom" title="Bottom">BOT</button>' +
                          '<div class="row"><button data-view="left" title="Left">L</button><button data-view="front" title="Front">F</button><button data-view="right" title="Right">R</button></div>' +
                          '<button data-view="back" title="Back">BCK</button>' +
                          '<button data-zoom="fit" title="Fit">FIT</button>' +
                          '<div style="font:bold 8px Arial;color:#333;text-align:center;margin-top:2px">Tỉ lệ 1:</div>' +
                          #{ratio_rows_html}
                          '<label class="ratio-custom">1:<input data-ratio-custom type="number" min="1" max="1000" value="#{escape_html(custom_ratio)}"></label>' +
                        '</div>' +
                        '<div class="view-ui-right no-print">' +
                          '<div class="vcontrol"><span>Explode</span><input data-explode type="range" min="0" max="3" step="0.1" value="0"></div>' +
                          '<div class="vcontrol"><span>Chân ID</span><input data-leader type="range" min="0" max="160" step="2" value="48"></div>' +
                          '<div class="checkcontrol">' +
                            '<label><input data-mono type="checkbox">Không màu</label>' +
                            '<label><input data-backedges type="checkbox">Back edge</label>' +
                          '</div>' +
                        '</div>' +
                        (page.warning ? '<div class="warn no-print" style="position:absolute;left:7mm;bottom:5mm;background:#fff;padding:3px 5px">' + esc(page.warning) + '</div>' : '') +
                      '</div>' +
                      '<div class="right">' +
                        miniHtml(page) +
                        '<div class="caption">' + esc(page.table_caption || (page.overview ? 'Danh sách module' : 'Danh sách tấm')) + '</div><div class="tablewrap">' + tableHtml(page) + '</div>' +
                      '</div>' +
                    '</div>' +
                    '<div class="title">' +
                      '<div class="cell"><div class="lb">Tên công trình</div><div class="vl">' + esc((page.title && page.title.project) || '') + '</div></div>' +
                      '<div class="cell"><div class="lb">Tên sản phẩm</div><div class="vl">' + esc(productTitle(page)) + '</div></div>' +
                      '<div class="cell"><div class="lb">Mã bản vẽ</div><div class="vl">' + esc(displayCode(page)) + '</div></div>' +
                      '<div class="cell"><div class="lb">Tỉ lệ</div><div class="vl scale-val">—</div></div>' +
                    '</div>' +
                  '</div>';
                root.appendChild(el);
                lazyInitViewer(el, el.querySelector('.viewer'), el.querySelector('.pins'), el.querySelector('.leaders'), page);
              }

              function esc(v) {
                return String(v == null ? '' : v).replace(/[&<>"']/g, function(ch) {
                  return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[ch];
                });
              }

              function displayCode(page) {
                return String(page.code || '') + (page.profile === 'no_door' ? ' - Không cánh' : '');
              }

              function productTitle(page) {
                const name = (page.title && page.title.product) || '';
                return String(name || '') + (page.profile === 'no_door' ? ' - Không cánh' : '');
              }

              function tableHtml(page) {
                if (page.overview) {
                  const rows = page.table_rows || [];
                  let s = '<table><tr><th class="c" style="width:40px">Mã</th><th>Module</th><th class="c" style="width:70px">Số chi tiết</th></tr>';
                  rows.forEach(function(r, i) {
                    s += '<tr><td class="c">' + esc(r.id == null ? i + 1 : r.id) + '</td><td>' + esc(r.name || '') + '</td><td class="c">' + esc(r.qty || 0) + '</td></tr>';
                  });
                  return s + '</table>';
                }
                if (page.table_rows && page.table_rows.length) {
                  let s = '<table><tr><th class="c" style="width:32px">ID</th><th style="width:110px">Tên tấm</th><th>Material</th></tr>';
                  page.table_rows.forEach(function(r, i) {
                    s += '<tr><td class="c">' + esc(r.id == null ? i + 1 : r.id) + '</td><td>' + esc(r.name || '') + '</td><td class="mat">' + esc(r.material || '') + '</td></tr>';
                  });
                  return s + '</table>';
                }
                let s = '<table><tr><th class="c" style="width:32px">ID</th><th style="width:110px">Tên tấm</th><th>Material</th></tr>';
                page.meshes.forEach(function(m, i) {
                  s += '<tr><td class="c">' + esc(m.id || i + 1) + '</td><td>' + esc(m.name || '') + '</td><td class="mat">' + esc(m.material || '') + '</td></tr>';
                });
                return s + '</table>';
              }

              function miniHtml(page) {
                if (!page.mini || !page.mini.base) {
                  return '<div class="mini"><div class="mini-empty">Mini-map</div></div>';
                }
                const overlay = page.mini.overlay ? '<img class="mini-overlay" src="' + esc(page.mini.overlay) + '">' : '';
                return '<div class="mini"><div class="mini-stack">' +
                  overlay +
                  '<img class="mini-base" src="' + esc(page.mini.base) + '">' +
                  '</div></div>';
              }

              const lazyViewers = [];
              const activeViewers = [];
              const maxActiveViewers = 3;
              let viewerObserver = null;

              function setActiveBtn(pageEl, selector, attr, value) {
                pageEl.querySelectorAll(selector).forEach(function(btn) {
                  btn.classList.toggle('active', btn.getAttribute(attr) === value);
                });
              }

              // Gắn sự kiện cho các nút/điều khiển của trang MỘT LẦN; mỗi lần dùng đọc DOM
              // và gọi viewer ĐANG sống (item.viewer). Tránh gắn chồng + giữ trạng thái khi
              // viewer bị hủy/khởi tạo lại (cuộn trang, chuẩn bị in).
              function bindPageControls(item) {
                if (item.bound) return;
                item.bound = true;
                const pageEl = item.pageEl;
                pageEl.querySelectorAll('button[data-view]').forEach(function(btn) {
                  btn.addEventListener('click', function() {
                    const name = btn.getAttribute('data-view');
                    setActiveBtn(pageEl, 'button[data-view]', 'data-view', name);
                    if (item.viewer) item.viewer.applyView(name);
                  });
                });
                pageEl.querySelectorAll('button[data-ratio]').forEach(function(btn) {
                  btn.addEventListener('click', function() {
                    const val = btn.getAttribute('data-ratio');
                    setActiveBtn(pageEl, 'button[data-ratio]', 'data-ratio', val);
                    if (item.viewer) item.viewer.setRatio(val);
                  });
                });
                const customRatio = pageEl.querySelector('input[data-ratio-custom]');
                if (customRatio) customRatio.addEventListener('change', function() {
                  const val = parseFloat(customRatio.value);
                  if (val > 0) {
                    pageEl.querySelectorAll('button[data-ratio]').forEach(function(btn) { btn.classList.remove('active'); });
                    if (item.viewer) item.viewer.setRatio(val);
                  }
                });
                const fitBtn = pageEl.querySelector('button[data-zoom="fit"]');
                if (fitBtn) fitBtn.addEventListener('click', function() { if (item.viewer) item.viewer.fit(); });
                const explode = pageEl.querySelector('input[data-explode]');
                if (explode) explode.addEventListener('input', function() { if (item.viewer) item.viewer.setExplode(parseFloat(explode.value) || 0); });
                const leader = pageEl.querySelector('input[data-leader]');
                if (leader) leader.addEventListener('input', function() { if (item.viewer) item.viewer.setLeader(parseFloat(leader.value) || 0); });
                const mono = pageEl.querySelector('input[data-mono]');
                if (mono) mono.addEventListener('change', function() { if (item.viewer) item.viewer.setMonochrome(!!mono.checked); });
                const backEdges = pageEl.querySelector('input[data-backedges]');
                if (backEdges) backEdges.addEventListener('change', function() { if (item.viewer) item.viewer.setBackEdges(!!backEdges.checked); });
              }

              function lazyInitViewer(pageEl, container, pinLayer, leaderLayer, page) {
                const item = { pageEl, container, pinLayer, leaderLayer, page, initialized:false, visible:false, viewer:null, bound:false };
                lazyViewers.push(item);
                bindPageControls(item);
                if ('IntersectionObserver' in window) {
                  if (!viewerObserver) {
                    viewerObserver = new IntersectionObserver(function(entries) {
                      entries.forEach(function(entry) {
                        const found = lazyViewers.find(function(v) { return v.pageEl === entry.target; });
                        if (!found) return;
                        found.visible = entry.isIntersecting;
                        if (entry.isIntersecting) {
                          initLazyItem(found);
                        } else {
                          trimActiveViewers();
                        }
                      });
                    }, { root:null, rootMargin:'700px 0px', threshold:0.01 });
                  }
                  viewerObserver.observe(pageEl);
                  if (lazyViewers.length <= 2) setTimeout(function() { initLazyItem(item); }, 80);
                } else {
                  initLazyItem(item);
                }
              }

              function initLazyItem(item) {
                if (item.initialized) {
                  touchViewer(item);
                  return;
                }
                item.initialized = true;
                item.viewer = initViewer(item.pageEl, item.container, item.pinLayer, item.leaderLayer, item.page);
                touchViewer(item);
                trimActiveViewers();
              }

              function touchViewer(item) {
                const idx = activeViewers.indexOf(item);
                if (idx >= 0) activeViewers.splice(idx, 1);
                activeViewers.push(item);
              }

              function trimActiveViewers() {
                while (activeViewers.length > maxActiveViewers) {
                  const idx = activeViewers.findIndex(function(item) { return !item.visible; });
                  if (idx < 0) return;
                  const victim = activeViewers.splice(idx, 1)[0];
                  if (victim.viewer && victim.viewer.dispose) victim.viewer.dispose();
                  victim.viewer = null;
                  victim.initialized = false;
                }
              }

              function preparePrint() {
                if (printBtn) {
                  printBtn.disabled = true;
                  printBtn.textContent = 'Đang chuẩn bị...';
                }
                let i = 0;
                function step() {
                  if (i >= lazyViewers.length) {
                    if (printBtn) {
                      printBtn.disabled = false;
                      printBtn.textContent = 'In PDF';
                    }
                    printPrepared = true;
                    setTimeout(function() { window.print(); }, 150);
                    return;
                  }
                  const item = lazyViewers[i++];
                  if (!item.viewer) {
                    item.viewer = initViewer(item.pageEl, item.container, item.pinLayer, item.leaderLayer, item.page);
                    item.initialized = true;
                  }
                  if (item.viewer && item.viewer.freezeForPrint) item.viewer.freezeForPrint();
                  if (item.viewer && item.viewer.dispose) item.viewer.dispose({ preserveSnapshot:true, preserveOverlays:true });
                  item.viewer = null;
                  item.initialized = false;
                  setTimeout(step, 20);
                }
                step();
              }

              function freezeAllForPrint() {
                lazyViewers.forEach(function(item) {
                  if (!item.viewer) {
                    item.viewer = initViewer(item.pageEl, item.container, item.pinLayer, item.leaderLayer, item.page);
                    item.initialized = true;
                  }
                  if (item.viewer && item.viewer.freezeForPrint) item.viewer.freezeForPrint();
                  if (item.viewer && item.viewer.dispose) item.viewer.dispose({ preserveSnapshot:true, preserveOverlays:true });
                  item.viewer = null;
                  item.initialized = false;
                });
              }

              function initViewer(pageEl, container, pinLayer, leaderLayer, page) {
                clearPrintSnapshot();
                // dispose({preserveOverlays:true}) lúc chuẩn bị in để giữ pin DOM cho ảnh in;
                // sau in, afterprint -> initLazyItem -> initViewer dựng lại CHƯA dọn lớp cũ -> pin cũ + pin mới chồng đè
                // -> "lỗi nhãn id". Dọn 2 lớp ở đầu mọi lần dựng (idempotent: lần đầu rỗng cũng không sao).
                if (pinLayer) pinLayer.innerHTML = '';
                if (leaderLayer) leaderLayer.innerHTML = '';
                const scene = new THREE.Scene();
                scene.background = new THREE.Color(0xffffff);
                const w = container.clientWidth || 1000;
                const h = container.clientHeight || 700;
                const aspect = w / h;
                const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 1000000);
                const renderer = new THREE.WebGLRenderer({ antialias:true, preserveDrawingBuffer:true });
                renderer.setSize(w, h);
                renderer.setPixelRatio(window.devicePixelRatio || 1);
                container.appendChild(renderer.domElement);

                const group = new THREE.Group();
                scene.add(group);
                const pins = [];
                const partObjects = [];
                const faceMeshes = [];
                const backEdgeLines = [];
                let leaderLength = 48;
                let monochromeEnabled = false;
                let backEdgesEnabled = false;
                let scaleRatio = null;   // null = AUTO (tự chọn tỉ lệ chuẩn vừa khung); số = mẫu N của 1:N
                const explicitLabels = page.labels && page.labels.length ? page.labels : null;
                const extraLabels = page.extra_labels && page.extra_labels.length ? page.extra_labels : [];
                page.meshes.forEach(function(m) {
                  const geom = new THREE.BufferGeometry();
                  geom.setAttribute('position', new THREE.Float32BufferAttribute(m.vertices, 3));
                  geom.computeVertexNormals();
                  geom.computeBoundingBox();
                  const mat = new THREE.MeshBasicMaterial({ color:m.color || 0xd8d8d8, side:THREE.DoubleSide, polygonOffset:true, polygonOffsetFactor:1, polygonOffsetUnits:1 });
                  const mesh = new THREE.Mesh(geom, mat);
                  mesh.userData.baseColor = m.color || 0xd8d8d8;
                  faceMeshes.push(mesh);
                  const partGroup = new THREE.Group();
                  partGroup.add(mesh);
                  group.add(partGroup);
                  const center = new THREE.Vector3();
                  if (geom.boundingBox && isFinite(geom.boundingBox.min.x)) {
                    geom.boundingBox.getCenter(center);
                  } else {
                    center.copy(centerFromArrays(m.edges, m.guides));
                  }
                  partGroup.userData.basePosition = partGroup.position.clone();
                  partGroup.userData.center = center.clone();
                  partObjects.push(partGroup);
                  if (!explicitLabels && m.pin !== false) addPin(m.id || (pins.length + 1), center, partGroup);
                  if (m.edges && m.edges.length) {
                    const eg = new THREE.BufferGeometry();
                    eg.setAttribute('position', new THREE.Float32BufferAttribute(m.edges, 3));
                    const solidEdgeMat = new THREE.LineBasicMaterial({ color:0x000000, transparent:false, opacity:1, depthTest:true });
                    const solidLine = new THREE.LineSegments(eg, solidEdgeMat);
                    solidLine.renderOrder = 2;
                    partGroup.add(solidLine);

                    const backEdgeMat = new THREE.LineDashedMaterial({ color:0x000000, transparent:true, opacity:0.35, depthTest:false, depthWrite:false, dashSize:2, gapSize:1 });
                    const backLine = new THREE.LineSegments(eg, backEdgeMat);
                    backLine.computeLineDistances();
                    backLine.renderOrder = 1;
                    backLine.visible = false;
                    backEdgeLines.push(backLine);
                    partGroup.add(backLine);
                  }
                  if (m.guides && m.guides.length) {
                    const gg = new THREE.BufferGeometry();
                    gg.setAttribute('position', new THREE.Float32BufferAttribute(m.guides, 3));
                    const guideMat = new THREE.LineDashedMaterial({ color:0x000000, transparent:true, opacity:0.85, depthTest:true, depthWrite:false, dashSize:4, gapSize:2 });
                    const guideLine = new THREE.LineSegments(gg, guideMat);
                    guideLine.computeLineDistances();
                    guideLine.renderOrder = 0;
                    partGroup.add(guideLine);
                  }
                });
                if (explicitLabels) {
                  explicitLabels.forEach(function(label, index) {
                    addPin(label.id == null ? index + 1 : label.id, new THREE.Vector3(label.point[0], label.point[1], label.point[2]), null);
                  });
                }
                extraLabels.forEach(function(label, index) {
                  addPin(label.id == null ? index + 1 : label.id, new THREE.Vector3(label.point[0], label.point[1], label.point[2]), null);
                });

                function centerFromArrays() {
                  let minX = Infinity, minY = Infinity, minZ = Infinity;
                  let maxX = -Infinity, maxY = -Infinity, maxZ = -Infinity;
                  for (let a = 0; a < arguments.length; a++) {
                    const arr = arguments[a] || [];
                    for (let i = 0; i + 2 < arr.length; i += 3) {
                      const x = arr[i], y = arr[i + 1], z = arr[i + 2];
                      minX = Math.min(minX, x); minY = Math.min(minY, y); minZ = Math.min(minZ, z);
                      maxX = Math.max(maxX, x); maxY = Math.max(maxY, y); maxZ = Math.max(maxZ, z);
                    }
                  }
                  if (!isFinite(minX)) return new THREE.Vector3(0, 0, 0);
                  return new THREE.Vector3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2);
                }

                function addPin(text, point, object) {
                  const pin = document.createElement('div');
                  pin.className = 'pin';
                  pin.textContent = text;
                  pinLayer.appendChild(pin);
                  const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
                  line.setAttribute('stroke', '#000');
                  line.setAttribute('stroke-width', '0.9');
                  const dot = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
                  dot.setAttribute('r', '2.2');
                  dot.setAttribute('fill', '#000');
                  leaderLayer.appendChild(line);
                  leaderLayer.appendChild(dot);
                  pins.push({ el:pin, line:line, dot:dot, point:point, object:object });
                }

                const b = page.bounds;
                const cx = (b.min[0] + b.max[0]) / 2, cy = (b.min[1] + b.max[1]) / 2, cz = (b.min[2] + b.max[2]) / 2;
                const sx = Math.max(1, b.max[0] - b.min[0]), sy = Math.max(1, b.max[1] - b.min[1]), sz = Math.max(1, b.max[2] - b.min[2]);
                const radius = Math.sqrt(sx*sx + sy*sy + sz*sz) || 1;
                const target = new THREE.Vector3(cx, cy, cz);
                const viewDirs = {
                  iso_fr: new THREE.Vector3(1, -1, 1),
                  iso_fl: new THREE.Vector3(-1, -1, 1),
                  iso_br: new THREE.Vector3(1, 1, 1),
                  iso_bl: new THREE.Vector3(-1, 1, 1),
                  top: new THREE.Vector3(0, 0, 1),
                  bottom: new THREE.Vector3(0, 0, -1),
                  front: new THREE.Vector3(0, -1, 0),
                  back: new THREE.Vector3(0, 1, 0),
                  left: new THREE.Vector3(-1, 0, 0),
                  right: new THREE.Vector3(1, 0, 0)
                };
                camera.up.set(0, 0, 1);

                // Fit bằng world units, không dùng pixel để set zoom. Dùng bbox diagonal-ish
                // vì góc iso chiếu cả X/Y/Z; margin lớn để chừa khung tên, pin và thao tác in.
                const fitSize = Math.max(sx + sy, sz + (sx + sy) * 0.35, radius * 1.15) * 1.55;
                camera.left = -fitSize * aspect / 2;
                camera.right = fitSize * aspect / 2;
                camera.top = fitSize / 2;
                camera.bottom = -fitSize / 2;
                camera.zoom = 1;
                camera.updateProjectionMatrix();

                const controls = new THREE.OrbitControls(camera, renderer.domElement);
                controls.target.copy(target);
                controls.addEventListener('change', renderAll);
                function clearPrintSnapshot() {
                  const img = container.querySelector('img.print-snapshot');
                  if (img && img.parentNode) img.parentNode.removeChild(img);
                  const canvas = container.querySelector('canvas');
                  if (canvas) canvas.style.display = '';
                }

                function renderAll() {
                  renderer.render(scene, camera);
                  updatePins();
                }

                // 1:N tự động = tỉ lệ chuẩn NHỎ NHẤT (vật to nhất) mà vẫn vừa vùng vẽ.
                function autoRatio() {
                  const nFit = (fitSize * INCH_MM) / PAPER_VIEW_H_MM; // N tại zoom=1 (đã có lề)
                  for (let k = 0; k < SCALE_STEPS.length; k++) {
                    if (SCALE_STEPS[k] >= nFit) return SCALE_STEPS[k];
                  }
                  return SCALE_STEPS[SCALE_STEPS.length - 1];
                }
                function currentRatio() { return scaleRatio || autoRatio(); }
                function zoomForRatio(n) { return (fitSize * INCH_MM) / (n * PAPER_VIEW_H_MM); }

                function updateScaleLabel() {
                  const el = pageEl.querySelector('.scale-val');
                  if (el) el.textContent = '1:' + currentRatio();
                }

                function fitCamera() {
                  camera.left = -fitSize * aspect / 2;
                  camera.right = fitSize * aspect / 2;
                  camera.top = fitSize / 2;
                  camera.bottom = -fitSize / 2;
                  camera.zoom = zoomForRatio(currentRatio());
                  camera.updateProjectionMatrix();
                  updateScaleLabel();
                }

                function setRatio(r) {
                  clearPrintSnapshot();
                  scaleRatio = (r == null || r === 'auto') ? null : (parseFloat(r) || null);
                  fitCamera();
                  renderAll();
                }

                function setLeader(n) {
                  clearPrintSnapshot();
                  leaderLength = n || 0;
                  renderAll();
                }

                function setView(name) {
                  clearPrintSnapshot();
                  const dir = (viewDirs[name] || viewDirs.iso_fr).clone().normalize();
                  camera.up.set(0, 0, 1);
                  if (name === 'top') camera.up.set(0, 1, 0);
                  if (name === 'bottom') camera.up.set(0, -1, 0);
                  camera.position.copy(target).add(dir.multiplyScalar(radius * 2.8));
                  controls.target.copy(target);
                  camera.lookAt(target);
                  fitCamera();
                  controls.update();
                  pageEl.querySelectorAll('button[data-view]').forEach(function(btn) {
                    btn.classList.toggle('active', btn.getAttribute('data-view') === name);
                  });
                  renderAll();
                }

                function setExplode(factor) {
                  partObjects.forEach(function(obj) {
                    const dir = obj.userData.center.clone().sub(target);
                    if (dir.lengthSq() < 1e-6) dir.set(1, 0, 0);
                    dir.normalize().multiplyScalar(radius * 0.08 * factor);
                    obj.position.copy(obj.userData.basePosition).add(dir);
                  });
                  renderAll();
                }

                function setMonochrome(enabled) {
                  clearPrintSnapshot();
                  monochromeEnabled = enabled;
                  faceMeshes.forEach(function(mesh) {
                    mesh.material.color.setHex(enabled ? 0xffffff : mesh.userData.baseColor);
                    mesh.material.needsUpdate = true;
                  });
                  applyEdgeStyle();
                  renderAll();
                }

                function setBackEdges(enabled) {
                  clearPrintSnapshot();
                  backEdgesEnabled = enabled;
                  applyEdgeStyle();
                  renderAll();
                }

                function applyEdgeStyle() {
                  backEdgeLines.forEach(function(line) {
                    line.visible = backEdgesEnabled;
                    line.material.depthTest = false;
                    line.material.depthWrite = false;
                    line.material.transparent = true;
                    line.material.opacity = 0.35;
                    line.material.color.setHex(0x000000);
                    if (backEdgesEnabled && line.material.isLineDashedMaterial) {
                      line.material.dashSize = Math.max(radius * 0.012, 1);
                      line.material.gapSize = Math.max(radius * 0.008, 0.6);
                    }
                    line.material.needsUpdate = true;
                  });
                }

                function updatePins() {
                  const rect = container.getBoundingClientRect();
                  leaderLayer.setAttribute('viewBox', '0 0 ' + rect.width + ' ' + rect.height);
                  const visiblePins = [];
                  pins.forEach(function(pin) {
                    const p = (pin.object ? pin.object.localToWorld(pin.point.clone()) : pin.point.clone()).project(camera);
                    const visible = p.x > -1.3 && p.x < 1.3 && p.y > -1.3 && p.y < 1.3;
                    pin.el.classList.toggle('hidden', !visible);
                    pin.line.style.display = visible ? '' : 'none';
                    pin.dot.style.display = visible ? '' : 'none';
                    if (!visible) return;
                    const ax = (p.x + 1) * 0.5 * rect.width;
                    const ay = (-p.y + 1) * 0.5 * rect.height;
                    let dx = ax - rect.width / 2;
                    let dy = ay - rect.height / 2;
                    const len = Math.hypot(dx, dy) || 1;
                    dx /= len;
                    dy /= len;
                    pin.anchor = { x: ax, y: ay };
                    pin.side = ax < rect.width / 2 ? -1 : 1;
                    pin.label = {
                      x: clamp(ax + dx * leaderLength, 14, rect.width - 14),
                      y: clamp(ay + dy * leaderLength, 14, rect.height - 14)
                    };
                    visiblePins.push(pin);
                  });

                  relaxPinLabels(visiblePins, rect.width, rect.height);

                  visiblePins.forEach(function(pin) {
                    const ax = pin.anchor.x;
                    const ay = pin.anchor.y;
                    const px = pin.label.x;
                    const py = pin.label.y;
                    pin.el.style.left = px + 'px';
                    pin.el.style.top = py + 'px';
                    pin.line.setAttribute('x1', ax);
                    pin.line.setAttribute('y1', ay);
                    pin.line.setAttribute('x2', px);
                    pin.line.setAttribute('y2', py);
                    pin.dot.setAttribute('cx', ax);
                    pin.dot.setAttribute('cy', ay);
                  });
                }

                function relaxPinLabels(items, width, height) {
                  const minDist = 26;
                  const pull = 0.035;
                  const maxDrift = Math.max(leaderLength * 0.65, 28);
                  items.forEach(function(pin) {
                    pin.home = { x: pin.label.x, y: pin.label.y };
                  });

                  for (let pass = 0; pass < 80; pass++) {
                    let moved = false;
                    for (let i = 0; i < items.length; i++) {
                      for (let j = i + 1; j < items.length; j++) {
                        const a = items[i].label;
                        const b = items[j].label;
                        let dx = b.x - a.x;
                        let dy = b.y - a.y;
                        let d = Math.hypot(dx, dy);
                        if (d < 0.001) {
                          dx = (j % 2) ? 1 : -1;
                          dy = (i % 2) ? 1 : -1;
                          d = Math.hypot(dx, dy);
                        }
                        if (d < minDist) {
                          const push = (minDist - d) * 0.52;
                          dx /= d;
                          dy /= d;
                          a.x -= dx * push;
                          a.y -= dy * push;
                          b.x += dx * push;
                          b.y += dy * push;
                          items[i].label.x += items[i].side * push * 0.35;
                          items[j].label.x += items[j].side * push * 0.35;
                          moved = true;
                        }
                      }
                    }

                    for (let i = 0; i < items.length; i++) {
                      for (let j = 0; j < items.length; j++) {
                        if (i === j) continue;
                        if (leaderHitsLabel(items[i], items[j])) {
                          items[i].label.x += items[i].side * 2.5;
                          items[i].label.y += (items[i].label.y >= items[j].label.y ? 1 : -1) * 2;
                          moved = true;
                        }
                      }
                    }

                    items.forEach(function(pin) {
                      pin.label.x += (pin.home.x - pin.label.x) * pull;
                      pin.label.y += (pin.home.y - pin.label.y) * pull;
                      const driftX = pin.label.x - pin.home.x;
                      const driftY = pin.label.y - pin.home.y;
                      const drift = Math.hypot(driftX, driftY);
                      if (drift > maxDrift) {
                        const k = maxDrift / drift;
                        pin.label.x = pin.home.x + driftX * k;
                        pin.label.y = pin.home.y + driftY * k;
                      }
                      pin.label.x = clamp(pin.label.x, 14, width - 14);
                      pin.label.y = clamp(pin.label.y, 14, height - 14);
                    });

                    if (!moved) break;
                  }
                }

                function leaderHitsLabel(leaderPin, labelPin) {
                  const r = 12;
                  const x1 = leaderPin.anchor.x;
                  const y1 = leaderPin.anchor.y;
                  const x2 = leaderPin.label.x;
                  const y2 = leaderPin.label.y;
                  const cx = labelPin.label.x;
                  const cy = labelPin.label.y;
                  if (Math.hypot(x2 - cx, y2 - cy) < r * 1.6) return false;
                  return pointSegmentDistance(cx, cy, x1, y1, x2, y2) < r;
                }

                function pointSegmentDistance(px, py, x1, y1, x2, y2) {
                  const dx = x2 - x1;
                  const dy = y2 - y1;
                  const l2 = dx * dx + dy * dy;
                  if (l2 < 1e-6) return Math.hypot(px - x1, py - y1);
                  let t = ((px - x1) * dx + (py - y1) * dy) / l2;
                  t = Math.max(0, Math.min(1, t));
                  return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy));
                }

                function clamp(value, min, max) {
                  return Math.max(min, Math.min(max, value));
                }

                // Áp trạng thái UI hiện tại đọc từ DOM -> giữ lựa chọn (góc, tỉ lệ, không màu,
                // back edge, leader, explode) mỗi khi viewer được DỰNG LẠI hoặc khi chuẩn bị IN.
                (function applyUiState() {
                  const ratioBtn = pageEl.querySelector('button[data-ratio].active');
                  const customRatio = pageEl.querySelector('input[data-ratio-custom]');
                  if (ratioBtn) {
                    scaleRatio = ratioBtn.getAttribute('data-ratio') !== 'auto'
                      ? (parseFloat(ratioBtn.getAttribute('data-ratio')) || null) : null;
                  } else if (customRatio && parseFloat(customRatio.value) > 0) {
                    scaleRatio = parseFloat(customRatio.value) || null;
                  } else {
                    scaleRatio = null;
                  }
                  const leadEl = pageEl.querySelector('input[data-leader]');
                  if (leadEl) leaderLength = parseFloat(leadEl.value) || 0;
                  const viewBtn = pageEl.querySelector('button[data-view].active');
                  setView(viewBtn ? viewBtn.getAttribute('data-view') : 'iso_fr');
                  const expEl = pageEl.querySelector('input[data-explode]');
                  if (expEl && parseFloat(expEl.value)) setExplode(parseFloat(expEl.value));
                  const monoEl = pageEl.querySelector('input[data-mono]');
                  if (monoEl && monoEl.checked) setMonochrome(true);
                  const beEl = pageEl.querySelector('input[data-backedges]');
                  if (beEl && beEl.checked) setBackEdges(true);
                })();

                return {
                  applyView: setView,
                  setMonochrome: setMonochrome,
                  setBackEdges: setBackEdges,
                  setLeader: setLeader,
                  setExplode: setExplode,
                  setRatio: setRatio,
                  fit: function() { clearPrintSnapshot(); fitCamera(); renderAll(); },
                  freezeForPrint: function() {
                    try {
                      renderAll();
                      let img = container.querySelector('img.print-snapshot');
                      if (!img) {
                        img = document.createElement('img');
                        img.className = 'print-snapshot';
                        container.appendChild(img);
                      }
                      img.src = renderer.domElement.toDataURL('image/png');
                    } catch (e) {}
                  },
                  dispose: function(options) {
                    options = options || {};
                    try {
                      controls.dispose();
                      scene.traverse(function(obj) {
                        if (obj.geometry) obj.geometry.dispose();
                        if (obj.material) {
                          if (Array.isArray(obj.material)) {
                            obj.material.forEach(function(mat) { if (mat.dispose) mat.dispose(); });
                          } else if (obj.material.dispose) {
                            obj.material.dispose();
                          }
                        }
                      });
                      renderer.dispose();
                      // GIẢI PHÓNG hẳn WebGL context: dispose() không tự mất context, dựng nhiều
                      // trang -> vượt giới hạn ~16 context -> toDataURL ra ảnh TRẮNG (mất hình khi in).
                      if (renderer.forceContextLoss) renderer.forceContextLoss();
                      if (renderer.domElement && renderer.domElement.parentNode) {
                        renderer.domElement.parentNode.removeChild(renderer.domElement);
                      }
                    } catch (e) {}
                    if (!options.preserveOverlays) {
                      pinLayer.innerHTML = '';
                      leaderLayer.innerHTML = '';
                    }
                  }
                };
              }

              PAGES.forEach(makePage);

              // Toggle "tất cả": set checkbox từng trang + viewer đang sống; trang chưa dựng vẫn
              // giữ trạng thái nhờ checkbox DOM (applyUiState đọc lại khi dựng/in).
              const allMono = document.getElementById('allMono');
              if (allMono) allMono.addEventListener('change', function() {
                lazyViewers.forEach(function(item) {
                  const cb = item.pageEl.querySelector('input[data-mono]');
                  if (cb) cb.checked = allMono.checked;
                  if (item.viewer) item.viewer.setMonochrome(allMono.checked);
                });
              });
              const allBack = document.getElementById('allBack');
              if (allBack) allBack.addEventListener('change', function() {
                lazyViewers.forEach(function(item) {
                  const cb = item.pageEl.querySelector('input[data-backedges]');
                  if (cb) cb.checked = allBack.checked;
                  if (item.viewer) item.viewer.setBackEdges(allBack.checked);
                });
              });
            </script>
          </body>
          </html>
        HTML
      end

      def escape_html(text)
        text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
      end

      class Bounds
        def initialize
          @min = [Float::INFINITY, Float::INFINITY, Float::INFINITY]
          @max = [-Float::INFINITY, -Float::INFINITY, -Float::INFINITY]
        end

        def add(x, y, z)
          vals = [x.to_f, y.to_f, z.to_f]
          3.times do |i|
            @min[i] = vals[i] if vals[i] < @min[i]
            @max[i] = vals[i] if vals[i] > @max[i]
          end
        end

        def to_h
          if @min.first.infinite?
            { min: [0, 0, 0], max: [1, 1, 1] }
          else
            { min: @min, max: @max }
          end
        end

        def center
          h = to_h
          3.times.map { |i| (h[:min][i] + h[:max][i]) / 2.0 }
        end
      end
    end
  end
end
