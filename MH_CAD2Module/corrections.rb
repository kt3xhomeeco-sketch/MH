# frozen_string_literal: true

require_relative 'model'
require_relative 'manual_boxes'

module MH
  module CAD2Module
    module Corrections
      module_function

      def active?
        @session && @session[:product].valid?
      end

      def status
        return nil unless active?
        { 'code' => @session[:analysis]['code'], 'id' => @session[:id], 'reason' => @session[:reason],
          'product_id' => @session[:product].persistent_id, 'activity_id' => @session[:analysis]['activity_id'],
          'manual' => !!@session[:manual], 'source_bounds' => @session[:analysis]['bounds'],
          'source_modules' => Array(@session[:before]['modules']).length }
      end

      def begin_session(product, reason)
        raise ArgumentError, 'Kết thúc phiên sửa hiện tại trước.' if active?
        raise ArgumentError, 'Chọn một sản phẩm/khối do CAD2Module dựng.' unless product
        root = Settings.library('library' => product.get_attribute(Model::DICT, 'library'))
        id = Ids.uuid
        analysis = JSON.parse(product.get_attribute(Model::DICT, 'analysis'))
        before = Model.state(product)
        snapshot = Storage.snapshot(root, product, "#{id}-before")
        event = Storage.event(root, 'kind' => 'error_report', 'session' => id, 'status' => 'unresolved',
                                    'reason' => reason, 'analysis' => analysis, 'before' => before, 'skp' => snapshot)
        @session = { id: id, product: product, model: product.model, root: root, analysis: analysis,
                     before: before, previous: before, reason: reason, initial_event: event }
        @observer ||= ChangeObserver.new
        product.model.add_observer(@observer)
        event
      end

      def record(kind = 'edit')
        return unless active?
        session = @session
        return if session[:manual]
        after = Model.state(session[:product])
        return if after == session[:previous]
        id = Ids.uuid
        snapshot = Storage.snapshot(session[:root], session[:product], "#{id}-after")
        Storage.event(session[:root], 'id' => id, 'kind' => kind, 'status' => 'pending',
                      'activity_id' => session[:analysis]['activity_id'], 'code' => session[:analysis]['code'],
                      'product_id' => session[:product].persistent_id,
                      'session' => session[:id], 'source_hash' => session[:analysis]['source_hash'],
                      'signature' => session[:analysis]['signature'], 'reason' => session[:reason],
                      'before' => session[:previous], 'after' => after, 'skp' => snapshot)
        session[:previous] = after
        CAD2Module.publish('Đã tự lưu thay đổi sửa lỗi.') if CAD2Module.respond_to?(:publish)
      end

      def finish
        raise ArgumentError, 'Chưa có phiên sửa.' unless active?
        return accept_manual if @session[:manual]
        record
        session = @session
        after = Model.state(session[:product])
        after['modules'].each { |mod| Placement.validate_module(mod) }
        raise ArgumentError, 'Sản phẩm chưa có module; phiên lỗi vẫn được giữ.' if after['modules'].empty?
        overlaps = after['modules'].combination(2).select { |a, b| Placement.overlap?(a, b) }
        raise ArgumentError, 'Các module đang chồng lấn; sửa trước khi nhận làm kinh nghiệm đúng.' unless overlaps.empty?
        if after['modules'].any? { |m| m['origin'][1] < -0.1 || m['origin'][2] < -0.1 }
          raise ArgumentError, 'Module đang vượt mặt trước Y=0 hoặc nằm dưới sàn Z=0.'
        end
        normalise_result(session, after)
        after = Model.state(session[:product])
        snapshot = Storage.snapshot(session[:root], session[:product], "#{session[:id]}-accepted")
        event = Storage.event(session[:root], 'kind' => 'correction', 'status' => 'accepted',
                              'session' => session[:id], 'signature' => session[:analysis].fetch('signature'),
                              'parser_version' => session[:analysis].fetch('parser_version', '0.1.0'),
                              'source_hash' => session[:analysis]['source_hash'], 'analysis' => session[:analysis],
                              'before' => session[:before], 'after' => after, 'skp' => snapshot, 'reason' => session[:reason])
        Storage.experience(session[:root], event) if after != session[:before] || session[:analysis]['manual_recovery']
        session[:model].remove_observer(@observer)
        @session = nil
        event
      end

      def begin_manual(product)
        begin_session(product, 'Người dùng đánh dấu Sai, sửa trực tiếp hoặc vẽ các box đúng')
        @session[:manual] = true
      end

      def accept_manual
        raise ArgumentError, 'Bấm Sai trước khi nhận các box đúng.' unless active? && @session[:manual]
        session = @session
        model = session[:model]; product = session[:product]
        capture = ManualBoxes.capture(model, product, model.selection.to_a)
        inputs = capture['source_ids'].map { |id| model.find_entity_by_persistent_id(id) }
        replacement = ManualBoxes.parts(capture, session[:analysis])
        offset = ManualBoxes.plan_offset(replacement, session[:analysis], capture)
        (replacement['modules'] + replacement['trim_parts']).each do |part|
          next unless part['source_box']
          part['source_box'] = part['source_box'].each_with_index.map { |v, i| v + offset[i % 2] }
          part['plan_box'] = part['source_box'].dup
        end
        analysis = JSON.parse(JSON.generate(session[:analysis])).merge(replacement)
        analysis['plan_origin_offset_mm'] = offset if ManualBoxes.plan_frame?(analysis)
        analysis['plan_origin_basis'] = 'source_plan_envelope' if ManualBoxes.plan_frame?(analysis)
        analysis.merge!('status' => 'ready', 'manual_boxes' => true)
        analysis.delete('envelope_preview')
        analysis['learning'] = { 'mode' => 'user_confirmed', 'message' => 'Bố trí từ các box người dùng đã xác nhận.' }
        if analysis['plan_engine'] == 'section-first-v1'
          analysis['height_source'] = 'user_confirmed'
          analysis['elevation_pending'] = false
          analysis['geometry_pipeline']['horizontal'].merge!('status' => 'user_confirmed', 'modules' => [], 'issues' => [])
        end
        analysis.delete('error')
        analysis['explanation'] = ['Kết quả do người dùng vẽ và xác nhận. Đo các đỉnh thực, chuẩn hóa cả bộ box, giữ vị trí tương đối; không phụ thuộc gốc/trục riêng.']
        transform = Geom::Transformation.new(capture['basis_transform'])
        if analysis.dig('placement', 'mode') == 'source_plan'
          if ManualBoxes.plan_frame?(analysis) && analysis['envelope']
            anchor = analysis.fetch('source_plan_envelope', analysis['envelope'])
            analysis['placement']['origin_mm'] = 2.times.map { |i| anchor[i] + offset[i] }
            transform = Geom::Transformation.new(Placement.source_matrix(analysis['placement']))
          else
            previous = session[:analysis].fetch('plan_origin_offset_mm', [0, 0])
            delta = 2.times.map { |i| offset[i] - previous[i] }
            transform *= Geom::Transformation.translation([*delta.map(&:mm), 0])
            analysis['placement']['origin_mm'] = 2.times.map { |i| analysis['placement']['origin_mm'][i] + delta[i] }
          end
        else
          labels = Model.labels(model).select { |label| label['code'] == analysis['code'] }
          raise ArgumentError, 'Nhãn SP bị mất hoặc trùng; khôi phục nhãn trước khi nhận box.' unless labels.length == 1
          transform = Geom::Transformation.translation([*Placement.named_origin(analysis, labels.first['center_x']).map(&:mm), 0])
        end
        model.start_operation('CAD2Module: Nhận Box', true)
        operation = true
        # Preserve the user's originals as hidden instances; canonical proxies
        # have stable axes for editing, templates and stored examples.
        product.make_unique if product.definition.instances.length > 1
        old = product.definition.entities.select { |e| Model.container?(e) && %w[module trim_reference panel_part].include?(e.get_attribute(Model::DICT, 'role')) }
        replacement['modules'].each { |part| Model.module_instance(product.definition.entities, part) }
        replacement['trim_parts'].each { |part| Model.reference_part(product.definition.entities, part) }
        old.each(&:erase!)
        product.transformation = transform
        product.set_attribute(Model::DICT, 'analysis', JSON.generate(analysis))
        product.hidden = false
        inputs.each { |e| e.hidden = true if e.valid? }
        after = Model.state(product)
        snapshot = Storage.snapshot(session[:root], product, "#{session[:id]}-manual-accepted")
        event = Storage.event(session[:root], 'kind' => 'correction', 'status' => 'accepted',
                              'session' => session[:id], 'signature' => session[:analysis].fetch('signature'),
                              'parser_version' => session[:analysis].fetch('parser_version'),
                              'source_hash' => session[:analysis]['source_hash'], 'analysis' => session[:analysis],
                              'before' => session[:before], 'after' => after, 'skp' => snapshot,
                              'reason' => session[:reason], 'manual_source_ids' => capture['source_ids'],
                              'normalised_from' => capture['normalised_from'], 'input_axes_ignored' => true,
                              'plan_origin_offset_mm' => offset, 'plan_origin_basis' => analysis['plan_origin_basis'],
                              'relinked_from_event' => session[:relinked_from_event])
        Storage.experience(session[:root], event)
        model.commit_operation
        operation = false
        model.remove_observer(@observer)
        @session = nil
        model.selection.clear
        model.selection.add(Model.selection_entities(product))
        event
      rescue StandardError
        model.abort_operation if operation
        raise
      end

      def cancel_manual
        raise ArgumentError, 'Chưa có phiên Sai đang mở.' unless active? && @session[:manual]
        session = @session
        session[:model].remove_observer(@observer)
        @session = nil
      end

      def normalise_result(session, state)
        product = session[:product]
        parts = state['modules'] + Array(state['trim_parts']) + Array(state['panel_parts'])
        minimum_x = parts.map { |m| m['origin'][0] }.min
        maximum_x = parts.map { |m| m['origin'][0] + m['size'][0] }.max
        bounds = state['bounds'].dup
        bounds[0] = maximum_x - minimum_x
        [1, 2].each do |axis|
          bounds[axis] = [bounds[axis], *parts.map { |m| m['origin'][axis] + m['size'][axis] }].max
        end
        on_source = session[:analysis].dig('placement', 'mode') == 'source_plan'
        label = on_source ? [] : Model.labels(session[:model]).select { |row| row['code'] == session[:analysis]['code'] }
        unless on_source || label.length == 1
          raise ArgumentError, 'Nhãn SP bị mất hoặc trùng; cần khôi phục nhãn trước khi kết thúc sửa.'
        end
        transact('Xác Nhận Kết Quả') do
          product.definition.entities.each do |entity|
            next unless %w[module trim_reference panel_part].include?(entity.get_attribute(Model::DICT, 'role'))
            unless minimum_x.abs < 0.001
              delta = Geom::Transformation.translation([-minimum_x.mm, 0, 0])
              delta = product.transformation * delta * product.transformation.inverse if product.is_a?(Assembly)
              entity.transform!(delta)
            end
          end
          product.transformation = if on_source
                                     product.transformation * Geom::Transformation.translation([minimum_x.mm, 0, 0])
                                   else
                                     placed = session[:analysis].merge('bounds' => bounds)
                                     Geom::Transformation.translation([*Placement.named_origin(placed, label.first['center_x']).map(&:mm), 0])
                                   end
          analysis = JSON.parse(product.get_attribute(Model::DICT, 'analysis'))
          analysis['placement']['origin_mm'][0] += minimum_x if on_source
          analysis['bounds'] = bounds
          analysis['trim_parts'] = Array(state['trim_parts']).map do |part|
            part.merge('origin' => [part['origin'][0] - minimum_x, *part['origin'][1..]])
          end
          analysis['panel_parts'] = Array(state['panel_parts']).map do |part|
            part.merge('origin' => [part['origin'][0] - minimum_x, *part['origin'][1..]])
          end
          product.set_attribute(Model::DICT, 'analysis', JSON.generate(analysis))
        end
      end

      def selected_module
        raise ArgumentError, 'Bật Sửa kết quả trước khi chỉnh module.' unless active?
        product = @session[:product]
        selection = product.model.selection.to_a
        entity = product.definition.entities.find do |item|
          selection.include?(item) && item.get_attribute(Model::DICT, 'role') == 'module'
        end
        raise ArgumentError, 'Chọn một Group module thuộc sản phẩm đang sửa.' unless entity
        [product, entity]
      end

      def transact(name)
        raise ArgumentError, 'Bật Sửa kết quả trước.' unless active?
        model = @session[:model]
        model.start_operation("CAD2Module: #{name}", true)
        operation = true
        yield @session[:product]
        model.commit_operation
        operation = false
        record
      rescue StandardError
        model.abort_operation if operation
        raise
      end

      def resize(size, origin = nil)
        product, selected = selected_module
        mod = Model.state(product)['modules'].find { |m| m['entity_id'] == selected.persistent_id }
        mod['size'] = size.map { |v| Float(v) }
        mod['origin'] = origin.map { |v| Float(v) } if origin
        mod['rule'] = 'user-correction'
        mod['explanation'] = 'Kích thước/vị trí do người dùng sửa; giữ liên kết với hình học CAD nguồn.'
        transact('đổi kích thước/vị trí') do
          Model.cube(product.definition.entities, mod)
          selected.erase!
        end
      end

      def split(axis, position)
        product, selected = selected_module
        mod = Model.state(product)['modules'].find { |m| m['entity_id'] == selected.persistent_id }
        axis = Integer(axis)
        cut = Float(position)
        raise ArgumentError, 'Vị trí chia phải nằm trong khối.' unless (0..2).cover?(axis) && cut > 0.1 && cut < mod['size'][axis] - 0.1
        first = JSON.parse(JSON.generate(mod))
        second = JSON.parse(JSON.generate(mod))
        first['size'][axis] = cut
        second['origin'][axis] += cut
        second['size'][axis] -= cut
        first['id'] = "M-#{Ids.hex(4)}"
        second['id'] = "M-#{Ids.hex(4)}"
        first['name'] = "#{mod['name']} A"
        second['name'] = "#{mod['name']} B"
        [first, second].each do |row|
          row['rule'] = 'user-split'
          row['explanation'] = 'Người dùng tách khối từ kết quả trước; xem lịch sử để đối chiếu.'
        end
        transact('tách module') do
          [first, second].each { |row| Model.cube(product.definition.entities, row) }
          selected.erase!
        end
      end

      def merge
        raise ArgumentError, 'Bật Sửa kết quả trước.' unless active?
        product = @session[:product]
        selected = product.model.selection.to_a
        mods = Model.state(product)['modules'].select do |mod|
          selected.any? { |e| e.persistent_id == mod['entity_id'] }
        end
        raise ArgumentError, 'Chọn ít nhất hai module trong cùng sản phẩm.' if mods.length < 2
        origin = 3.times.map { |i| mods.map { |m| m['origin'][i] }.min }
        maximum = 3.times.map { |i| mods.map { |m| m['origin'][i] + m['size'][i] }.max }
        size = 3.times.map { |i| maximum[i] - origin[i] }
        volume = mods.sum { |m| m['size'].inject(:*) }
        raise ArgumentError, 'Các khối chưa ghép kín hình hộp; không gộp xuyên khoảng trống.' if (volume - size.inject(:*)).abs > 0.001 * size.inject(:*)
        mod = { 'id' => "M-#{Ids.hex(4)}", 'name' => 'Module gộp', 'origin' => origin, 'size' => size }
        mod['handles'] = mods.flat_map { |row| row['handles'] || [] }.uniq
        mod['rule'] = 'user-merge'
        mod['explanation'] = 'Người dùng gộp các khối liền kề thành một thùng.'
        transact('gộp module') do
          Model.cube(product.definition.entities, mod)
          selected.each { |e| e.erase! if mods.any? { |m| m['entity_id'] == e.persistent_id } }
        end
      end

      def add(size, origin)
        mod = { 'id' => "M-#{Ids.hex(4)}", 'name' => 'Module bổ sung',
                'size' => size.map { |v| Float(v) }, 'origin' => origin.map { |v| Float(v) } }
        transact('bổ sung module') { |product| Model.cube(product.definition.entities, mod) }
      end

      class ChangeObserver < Sketchup::ModelObserver
        def onTransactionCommit(_model)
          schedule('edit')
        end

        def onTransactionUndo(_model)
          schedule('undo')
        end

        def onTransactionRedo(_model)
          schedule('redo')
        end

        def schedule(kind)
          @generation = (@generation || 0) + 1
          generation = @generation
          UI.start_timer(0.15, false) do
            next unless generation == @generation
            Corrections.record(kind)
          rescue StandardError => error
            CAD2Module.report_error("Không tự lưu được sửa lỗi: #{error.message}")
          end
        end
      end
    end
  end
end
