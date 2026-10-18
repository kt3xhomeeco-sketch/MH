# frozen_string_literal: true

require 'sketchup.rb'
require_relative 'jobs'
require_relative 'model'
require_relative 'corrections'
require_relative 'templates'
require_relative 'selection_source'
require_relative 'scan_tool'
require_relative 'plan_rules'
require_relative 'activity'

module MH
  # SketchUp is the user surface; the local worker owns CAD parsing only.
  module CAD2Module
    extend self

    def manager
      @manager ||= make_dialog('MH CAD2Module — Quản lý', 'manager.html', 1100, 780, 'manager')
      @manager.show
      publish
    end

    def entry(mode = 'dwg')
      @entry_mode = mode
      @entry ||= make_dialog('MH CAD2Module — Dựng sản phẩm', 'entry.html', 420, 235, 'entry')
      @entry.show
      publish
    end

    def start_scan
      raise ArgumentError, 'Kết thúc Sửa kết quả trước khi quét nguồn mới.' if Corrections.active?
      @selection_geometry = nil
      Sketchup.active_model.select_tool(ScanTool.new)
      publish('Kéo khung bao mặt bằng CAD; thả chuột để dựng ngay tại vùng quét, không cần nhập mã SP.')
    end

    def selection_ready(window)
      @selection_geometry = SelectionSource.capture(Sketchup.active_model, window: window)
      @entry_mode = 'selection'
      build_request('')
    end

    def make_dialog(title, page, width, height, key)
      dialog = UI::HtmlDialog.new(dialog_title: title, preferences_key: "MH_CAD2Module.#{key}",
                                  scrollable: true, resizable: true, width: width, height: height,
                                  style: UI::HtmlDialog::STYLE_DIALOG)
      dialog.set_file(File.join(Settings::ROOT, 'ui', page))
      dialog.add_action_callback('request') do |_context, raw|
        packet = JSON.parse(raw)
        dispatch(packet)
      rescue StandardError => error
        report_error(error.message, activity_key: packet && packet['activity_key'])
      end
      dialog.set_on_closed do
        if key == 'manager'
          @manager = nil if @manager.equal?(dialog)
        else
          @entry = nil if @entry.equal?(dialog)
        end
      end
      dialog
    end

    def products
      Array(@analyses).flat_map { |analysis| analysis['products'] || [] }
    end

    def public_state
      selected = Model.selected_product
      selected_module = Sketchup.active_model.selection.find do |entity|
        entity.get_attribute(Model::DICT, 'role') == 'module'
      end
      evidence = selected_module ? JSON.parse(selected_module.get_attribute(Model::DICT, 'source_module', '{}')) : nil
      focused = if @history_product
                  @history_product
                elsif @focus_cad
                  products.find { |p| p['code'] == @focused }
                elsif selected
                  JSON.parse(selected.get_attribute(Model::DICT, 'analysis'))
                else
                  products.find { |p| p['code'] == @focused } || products.first
                end
      settings = Settings.read
      activity_rows, activity_detail = activity_state
      focused = activity_detail['analysis'] if activity_detail && activity_detail['analysis']
      if activity_detail
        evidence = nil unless selected && selected.persistent_id.to_s == activity_detail['product_id'].to_s
        selected = activity_detail['product_id'] && Model.product_by_id(Sketchup.active_model, activity_detail['product_id'])
      end
      { 'settings' => settings, 'busy' => Jobs.busy?, 'message' => @message,
        'activities' => activity_rows, 'activity_detail' => activity_detail,
        'plan_rules' => PlanRules.status(settings['library']),
        'errors' => @errors || [], 'labels' => Model.labels,
        'products' => products.map { |p| p.slice('code', 'name', 'automatic_scan', 'status', 'error', 'bounds', 'source_path') },
        'focused' => focused, 'correction' => Corrections.status, 'manual_acceptance' => @manual_acceptance,
        'current_modules' => selected ? Model.state(selected)['modules'] : [],
        'last_products' => @last_products || '', 'selected_evidence' => evidence }
        .merge('entry_mode' => @entry_mode || 'dwg')
    end

    def history
      root = Settings.resolve_library(Settings.read['library'])
      File.directory?(root) ? Storage.history(root) : []
    end

    def activity_state
      model = Sketchup.active_model
      live = Model.products(model)
      root = Settings.resolve_library(Settings.read['library'])
      rows = Activity.rows(root, live)
      focus = @activity_focus if @activity_focus && @activity_focus[:model].equal?(model)
      row = rows.find { |item| item['key'] == focus[:key] } if focus
      detail = Activity.detail(Settings.resolve_library(row['library']), row, live) if row
      [rows, detail]
    end

    def open_activity(identity)
      row = activity_state.first.find { |item| item['key'] == identity }
      raise ArgumentError, 'Không thấy quá trình này trong model/thư viện hiện tại.' unless row
      status = Corrections.status
      if status && status['product_id'].to_s != row['product_id'].to_s
        raise ArgumentError, 'Kết thúc hoặc hủy sửa SP đang mở trước khi đổi sang SP khác.'
      end
      @activity_focus = { model: Sketchup.active_model, key: identity }
      @history_product = nil
      publish
    end

    def dispatch_activity(packet)
      row = activity_state.first.find { |item| item['key'] == packet['activity_key'] }
      raise ArgumentError, 'Không thấy quá trình của SP này; làm mới bảng.' unless row
      raise ArgumentError, 'Chờ tác vụ đang chạy hoàn tất.' if Jobs.busy?
      action = packet.fetch('action')
      if action == 'accept_manual_boxes' && @manual_acceptance &&
         @manual_acceptance['request_id'] == packet['request_id'] && @manual_acceptance['activity_key'] == row['key']
        return accept_manual_boxes(packet['request_id'], packet['session_id'])
      end
      status = Corrections.status
      if status && status['product_id'].to_s != row['product_id'].to_s
        raise ArgumentError, 'Nút này thuộc SP khác với phiên sửa đang mở.'
      end
      product = row['product_id'] && Model.product_by_id(Sketchup.active_model, row['product_id'])
      if !product && action == 'begin_correction' && !row['ambiguous'] && !status
        analysis = Activity.detail(Settings.resolve_library(row['library']), row, Model.products)['analysis']
        if analysis && analysis['status'] == 'needs_review' && analysis['signature']
          product = recover_product(analysis, Settings.resolve_library(row['library']))
        end
      end
      raise ArgumentError, 'Bộ khối của SP này đã bị xóa hoặc không xác định duy nhất; không chọn nhầm SP khác.' unless product
      @activity_focus = { model: Sketchup.active_model, key: row['key'] }
      case action
      when 'select_activity'
        model = Sketchup.active_model
        model.active_path = nil if model.active_path
        model.selection.clear
        model.selection.add(Model.selection_entities(product))
        @history_product = nil
        @focus_cad = false
        publish('Đã Select toàn bộ khối được tạo của SP này.')
      when 'wrong' then mark_wrong(product)
      when 'select_module' then select_module(packet.fetch('id'), product)
      when 'begin_correction' then begin_correction(packet['reason'], product)
      when 'accept_manual_boxes', 'cancel_manual_boxes', 'finish_correction', 'resize', 'split', 'merge', 'add_module', 'template'
        raise ArgumentError, 'Chưa có phiên sửa cho SP này; bấm Sai trước.' unless status
        dispatch(packet.reject { |key, _value| key == 'activity_key' })
      else raise ArgumentError, 'Thao tác không thuộc quá trình sản phẩm.'
      end
    end

    def publish(message = nil)
      @message = message if message
      json = JSON.generate(public_state)
      [@manager, @entry].compact.each do |dialog|
        dialog.execute_script("window.receive && window.receive(#{json})") if dialog.visible?
      end
    end

    def report_error(message, analysis: nil, activity_key: nil)
      if activity_key
        row = activity_state.first.find { |item| item['key'] == activity_key }
        analysis ||= Activity.detail(Settings.resolve_library(row['library']), row, Model.products)['analysis'] if row
      end
      @errors ||= []
      code = analysis && analysis['code']
      code ||= message[/\bSP\d+\b/i]
      selected = Model.selected_product
      code ||= selected.get_attribute(Model::DICT, 'code') if selected
      @errors << { 'error' => message, 'time' => Time.now.strftime('%H:%M:%S'), 'code' => code, 'activity_id' => analysis && analysis['activity_id'] }
      @errors = @errors.last(100)
      begin
        root = row ? Settings.resolve_library(row['library']) : Settings.library
        Storage.event(root, 'kind' => 'error', 'status' => 'unresolved', 'error' => message, 'analysis' => analysis, 'code' => code)
      rescue ArgumentError, SystemCallError
        # Configuration errors are shown before a usable library exists.
      end
      manager unless @manager&.visible?
      publish(message)
    end

    def dispatch(packet)
      return dispatch_activity(packet) if packet['activity_key']
      action = packet.fetch('action')
      case action
      when 'activity_open' then open_activity(packet.fetch('key'))
      when 'activity_close' then @activity_focus = nil; publish
      when 'ready', 'refresh' then publish
      when 'manager' then manager
      when 'entry' then entry
      when 'entry_selection', 'scan_selection' then start_scan
      when 'save_settings' then Settings.save(packet.fetch('settings')); publish('Đã nhớ cấu hình theo model/dự án.')
      when 'choose_library' then choose_library
      when 'choose_source' then choose_source
      when 'choose_python', 'choose_converter' then choose_program(action)
      when 'scan' then scan
      when 'build' then build_request(packet.fetch('products', ''))
      when 'cancel' then Jobs.cancel; publish('Đã hủy tác vụ; các bản nguồn đã lưu vẫn được giữ.')
      when 'excel' then excel
      when 'focus' then @history_product = nil; @focused = packet.fetch('code'); @focus_cad = true; publish
      when 'history' then show_history(packet.fetch('id'))
      when 'focus_error' then focus_error(packet.fetch('code'))
      when 'explain' then @history_product = nil; @focus_cad = false; manager; publish('Đang hiển thị bằng chứng của sản phẩm/khối được chọn.')
      when 'begin_correction' then begin_correction(packet['reason'])
      when 'wrong' then mark_wrong
      when 'accept_manual_boxes' then accept_manual_boxes(packet['request_id'], packet['session_id'])
      when 'manual_acceptance_status' then manual_acceptance_status(packet.fetch('request_id'))
      when 'cancel_manual_boxes' then Corrections.cancel_manual; @manual_acceptance = nil; publish('Đã hủy nhận box; kết quả cũ hiện lại, các box mày vẽ giữ nguyên.')
      when 'finish_correction' then Corrections.finish; publish('Đã lưu kết quả đúng và kinh nghiệm theo cấu tạo.')
      when 'select_module' then select_module(packet.fetch('id'))
      when 'resize' then resize_dialog
      when 'split' then split_dialog
      when 'merge' then Corrections.merge; publish
      when 'add_module' then add_dialog
      when 'template' then replace_template
      when 'mark_region' then mark_region(packet.fetch('box'))
      else raise ArgumentError, "Thao tác chưa được hỗ trợ: #{action}"
      end
    end

    def choose_library
      raise ArgumentError, 'Chờ tác vụ CAD và kết thúc sửa trước khi chuyển thư viện.' if Jobs.busy? || Corrections.active?
      path = UI.select_directory(title: 'Chọn nơi chuyển thư viện CAD và kinh nghiệm', directory: Settings.read['library'])
      return unless path
      Settings.relocate(path)
      publish('Đã sao chép thư viện và cập nhật đường dẫn. Bản cũ được giữ nguyên.')
    end

    def choose_source
      path = UI.openpanel('Thêm nguồn CAD', nil, 'CAD|*.dwg;*.dxf||')
      return unless path
      Settings.save('sources' => (Settings.read['sources'] + [path]).uniq)
      publish('Đã nhớ đường dẫn CAD. Lần sau chỉ nhập SP cần dựng.')
    end

    def choose_program(action)
      path = UI.openpanel(action == 'choose_python' ? 'Chọn python.exe' : 'Chọn ODAFileConverter.exe', nil, 'EXE|*.exe||')
      return unless path
      Settings.save((action == 'choose_python' ? 'python' : 'converter') => path)
      publish('Đã cập nhật công cụ đọc CAD.')
    end

    def scan(values = {}, &completion)
      @errors = []
      action = values.delete('action') || 'analyze'
      Jobs.start(action, values) do |result, job|
        if !job[:model].equal?(Sketchup.active_model)
          report_error('Model hiện tại đã đổi trong lúc đọc. Kết quả tác vụ vẫn nằm trong thư viện; đọc lại ở model cần dựng.')
        elsif result['ok']
          @analyses = result['analyses']
          @history_product = nil
          @errors = result['errors'] || []
          @analyses.each do |analysis|
            analysis['products'].each do |product|
              product['activity_id'] = Ids.uuid
              Storage.event(job[:root], 'kind' => 'scan', 'status' => product['status'], 'job_id' => job[:id],
                                        'analysis' => product, 'model_path' => job[:model].path)
            end
            analysis['diagnostics'].each { |text| @errors << { 'source' => analysis['revision']['original_path'], 'error' => text } }
          end
          @activity_focus = nil
          publish("Đã đọc #{products.length} sản phẩm từ hình học CAD.")
          completion.call(job) if completion
        else
          failed = if values['code']
                     { 'code' => values['code'], 'name' => values['name'], 'automatic_scan' => values['automatic_scan'],
                       'activity_id' => Ids.uuid, 'status' => 'needs_review', 'source_hash' => values.dig('geometry', 'hash') }
                   end
          report_error(result.fetch('error', 'Bộ đọc CAD chưa trả kết quả.'), analysis: failed)
        end
      end
      publish('Đang lưu phiên bản CAD và phân tích hình học…')
    end

    def build_request(text)
      raise ArgumentError, 'Kết thúc Sửa kết quả trước khi dựng SP khác.' if Corrections.active?
      if @entry_mode == 'selection'
        values = SelectionSource.build_request(@selection_geometry || SelectionSource.capture)
        requests = [values['code']]
      else
        requests = text.to_s.split(/[\r\n,;]+/).map(&:strip).reject(&:empty?).uniq
        raise ArgumentError, 'Nhập tên hoặc mã SP cần dựng.' if requests.empty?
        @last_products = text.to_s
        values = { 'targets' => requests }
      end
      scan(values) do |job|
        built = []
        requests.each do |request|
          matches = products.select do |product|
            Model.normalise(product['code']) == Model.normalise(request) || fold(product['name']) == fold(request)
          end
          if matches.empty?
            report_error("Không tìm thấy sản phẩm #{request} trong nguồn đã cấu hình.")
          elsif matches.length > 1
            report_error("#{request} khớp nhiều sản phẩm/nguồn. Nhập mã SP duy nhất hoặc giữ đúng nguồn của dự án.")
          else
            begin
              built << Model.build(matches.first, job[:root], job[:id], job[:model])
              @focused = matches.first['code']
              @focus_cad = false
            rescue StandardError => error
              report_error(error.message, analysis: matches.first)
            end
          end
        end
        unless built.empty?
          model = job[:model]
          @last_built = { model: model, ids: built.map(&:persistent_id) }
          model.selection.clear
          model.selection.add(built.flat_map { |product| Model.selection_entities(product) })
        end
        publish("Đã dựng #{built.length}/#{requests.length} SP. Lỗi chi tiết ở bảng Quản lý.")
      end
    end

    def fold(value)
      value.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').tr('đĐ', 'dD').upcase.strip
    end

    def excel
      path = UI.openpanel('Danh sách sản phẩm cần dựng', nil, 'Danh sách|*.xlsx;*.xlsm;*.csv;*.tsv||')
      return unless path
      Jobs.start('products', 'path' => path) do |result, _job|
        if result['ok']
          @last_products = result.fetch('products').join("\n")
          entry
          publish("Đã lấy #{result['products'].length} SP từ danh sách; bấm Dựng để thực hiện.")
        else
          report_error(result.fetch('error'))
        end
      end
      publish('Đang đọc danh sách sản phẩm…')
    end

    def begin_correction(reason = nil, product = nil)
      product ||= Model.selected_product
      product ||= recover_product
      Corrections.begin_session(product, reason.to_s.empty? ? 'Sửa kết quả chia module' : reason)
      @activity_focus = { model: Sketchup.active_model, key: Activity.key(JSON.parse(product.get_attribute(Model::DICT, 'analysis'))) }
      manager
      publish('Đang sửa kết quả. Các thay đổi khối được tự lưu; chọn Kết thúc sửa khi đã đúng.')
    end

    def correction_target
      product = Model.selected_product
      if !product && @last_built && @last_built[:model] == Sketchup.active_model
        candidates = @last_built[:ids].filter_map { |id| Model.product_by_id(Sketchup.active_model, id) }
        product = candidates.first if candidates.length == 1
      end
      raise ArgumentError, 'Chọn đúng khối sản phẩm cần sửa rồi bấm Sai; app không tự chọn sản phẩm cũ.' unless product
      product
    end

    def mark_wrong(product = nil)
      raise ArgumentError, 'Chờ tác vụ dựng hoàn tất trước khi bấm Sai.' if Jobs.busy?
      product ||= correction_target
      Corrections.begin_manual(product)
      @activity_focus = { model: Sketchup.active_model, key: Activity.key(JSON.parse(product.get_attribute(Model::DICT, 'analysis'))) }
      @manual_acceptance = nil
      manager
      publish('Đã ghi Sai và tạm ẩn kết quả cũ. Vẽ mỗi box đúng thành một Group/Component; không cần tên, gốc hoặc trục riêng. Chọn các box trong SketchUp rồi bấm Kết quả đúng.')
    end

    def emit_manual_acceptance(result)
      if @manager&.visible?
        @manager.execute_script("window.receiveManualAcceptance && window.receiveManualAcceptance(#{JSON.generate(result)})")
      end
      result
    end

    def manual_acceptance_status(request_id)
      result = if @manual_acceptance && @manual_acceptance['request_id'] == request_id
                 @manual_acceptance
               else
                 { 'status' => 'unknown', 'request_id' => request_id }
               end
      emit_manual_acceptance(result)
    end

    def accept_manual_boxes(request_id = nil, session_id = nil)
      if request_id && @manual_acceptance && @manual_acceptance['request_id'] == request_id
        return emit_manual_acceptance(@manual_acceptance)
      end
      if session_id && Corrections.status&.fetch('id') != session_id
        raise ArgumentError, 'Phiên sửa đã thay đổi; chọn đúng sản phẩm và bắt đầu lại.'
      end
      @manual_acceptance = { 'status' => 'processing', 'request_id' => request_id }
      emit_manual_acceptance(@manual_acceptance)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      event = Corrections.accept_manual
      @focus_cad = false
      @manual_acceptance = { 'status' => 'saved', 'request_id' => request_id, 'code' => event.dig('analysis', 'code'),
                             'activity_key' => Activity.key(event['analysis']),
                             'modules' => event['after']['modules'].length,
                             'auxiliary' => Array(event['after']['trim_parts']).length,
                             'elapsed_ms' => ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2) }
      emit_manual_acceptance(@manual_acceptance)
      publish('Đã nhận Kết quả đúng và lưu mẫu từ các box mày đã vẽ.')
      PlanRules.enqueue(event)
      event
    rescue StandardError => error
      @manual_acceptance = { 'status' => 'error', 'request_id' => request_id, 'message' => error.message } unless event
      emit_manual_acceptance(@manual_acceptance)
      raise
    end

    def recover_product(focused = nil, root = nil)
      focused ||= products.find { |row| row['code'] == @focused } || products.first
      raise ArgumentError, 'Chọn một sản phẩm đã dựng hoặc một SP cần kiểm tra trong bảng CAD.' unless focused
      raise ArgumentError, 'Chọn khối SP đã dựng trong model để bắt đầu sửa.' if focused['status'] == 'ready'
      raise ArgumentError, 'Nguồn chưa có hình học để lưu kinh nghiệm.' unless focused['signature']
      values = UI.inputbox(['Rộng SP đã xác minh (mm)', 'Sâu SP đã xác minh (mm)', 'Cao SP đã xác minh (mm)'],
                           ['', '', ''], 'Tạo khối sửa cho SP chưa nhận dạng được')
      raise ArgumentError, 'Đã hủy tạo khối sửa; hồ sơ lỗi vẫn được giữ.' unless values
      size = values.map { |value| Float(value) }
      manual = JSON.parse(JSON.generate(focused))
      manual['activity_id'] ||= Activity.key(focused)
      manual.merge!('status' => 'ready', 'bounds' => size, 'manual_recovery' => true,
                    'modules' => [{ 'id' => 'M01', 'name' => 'Khối sửa theo người dùng', 'origin' => [0, 0, 0], 'size' => size }])
      manual['explanation'] = [focused['error'], 'Khối đối chiếu do người dùng nhập kích thước đã xác minh.']
      Model.build(manual, root || Settings.library, "recovery-#{Ids.uuid}")
    end

    def select_module(id, product = nil)
      product ||= Model.selected_product
      raise ArgumentError, 'Chọn sản phẩm trong model trước.' unless product
      entity = product.definition.entities.find { |e| e.persistent_id.to_s == id.to_s }
      raise ArgumentError, 'Module đã thay đổi; làm mới bảng.' unless entity
      path = product.is_a?(Assembly) ? nil : [product]
      product.model.active_path = path unless product.model.active_path == path
      product.model.selection.clear
      product.model.selection.add(entity)
      @focus_cad = false
      publish
    end

    def focus_error(code)
      @history_product = nil
      @focused = code
      product = Model.products.find { |item| item.get_attribute(Model::DICT, 'code') == code }
      @focus_cad = !product
      if product
        product.model.active_path = nil
        product.model.selection.clear
        entities = Model.selection_entities(product)
        product.model.selection.add(entities)
        product.model.active_view.zoom(entities)
      end
      publish('Đã chọn SP và vùng CAD liên quan đến lỗi.')
    end

    def show_history(id)
      root = Settings.library
      row = Storage.history(root).find { |item| item['id'] == id }
      raise ArgumentError, 'Không thấy hồ sơ trong thư viện hiện tại.' unless row
      file = row.fetch('file')
      raise ArgumentError, 'Đường dẫn hồ sơ không hợp lệ.' unless File.basename(file) == file
      event = JSON.parse(File.read(File.join(root, 'history', file), encoding: 'UTF-8'))
      @history_product = event['analysis']
      if @history_product
        @history_product['explanation'] ||= []
        @history_product['explanation'] << "Hồ sơ #{event['time']}: #{event['reason'] || event['kind']}"
        if event['after']
          before_count = event.dig('before', 'modules')&.length
          after_count = event.dig('after', 'modules')&.length
          @history_product['explanation'] << "Số khối trước/sau sửa: #{before_count} → #{after_count}. Bản SKP đối chiếu đã lưu độc lập."
        end
      end
      publish("Hồ sơ tự lưu: #{event['reason'] || event['error'] || event['kind']} · #{event['status']}")
    end

    def resize_dialog
      product, selected = Corrections.selected_module
      mod = Model.state(product)['modules'].find { |m| m['entity_id'] == selected.persistent_id }
      values = UI.inputbox(['Rộng X (mm)', 'Sâu Y (mm)', 'Cao Z (mm)', 'Gốc X nội bộ', 'Gốc Y nội bộ', 'Gốc Z nội bộ'],
                           mod['size'] + mod['origin'], 'Sửa kích thước / vị trí module')
      return unless values
      Corrections.resize(values.first(3), values.last(3))
      publish
    end

    def split_dialog
      _product, selected = Corrections.selected_module
      values = UI.inputbox(['Trục chia', 'Khoảng cách từ mép đầu (mm)'], ['X', 400], ['X|Y|Z', ''], "Tách #{selected.name}")
      return unless values
      Corrections.split(%w[X Y Z].index(values[0]), values[1])
      publish
    end

    def add_dialog
      values = UI.inputbox(['Rộng X', 'Sâu Y', 'Cao Z', 'Gốc X nội bộ', 'Gốc Y nội bộ', 'Gốc Z nội bộ'],
                           [800, 582, 2100, 0, 18, 50], 'Bổ sung khối bị thiếu — mm')
      return unless values
      Corrections.add(values.first(3), values.last(3))
      publish
    end

    def replace_template
      path = UI.openpanel('Chọn module mẫu SketchUp', nil, 'SketchUp|*.skp||')
      return unless path
      Templates.replace(path)
      publish('Đã thay module mẫu, giữ vị trí và kiểm tra kích thước.')
    end

    def mark_region(box)
      raise ArgumentError, 'Vùng CAD chưa hợp lệ.' unless box.is_a?(Array) && box.length == 4 && box.all? { |v| v.is_a?(Numeric) && v.finite? }
      focused = public_state['focused']
      raise ArgumentError, 'Chọn SP trong bảng trước khi đánh dấu.' unless focused
      Storage.event(Settings.library, 'kind' => 'source_region_report', 'status' => 'unresolved',
                    'code' => focused['code'], 'source_hash' => focused['source_hash'], 'box' => box,
                    'reason' => 'Người dùng đánh dấu vùng CAD cần kiểm tra/bổ sung.')
      publish('Đã lưu vùng CAD được đánh dấu vào hồ sơ lỗi; vùng này chưa tự trở thành mẫu đúng.')
    end

    def install
      return if @installed
      @installed = true
      menu = UI.menu('Extensions').add_submenu('MH CAD2Module')
      [['Dựng sản phẩm…', method(:entry)], ['Quản lý / CAD / Lỗi…', method(:manager)],
       ['Quét chọn nét CAD…', method(:start_scan)],
       ['Vì sao dựng như vậy?', -> { dispatch('action' => 'explain') }],
       ['Sửa kết quả đang chọn', -> { dispatch('action' => 'begin_correction') }]].each do |label, callback|
        menu.add_item(label) { callback.call }
      end
      @toolbar = UI::Toolbar.new('MH CAD2Module')
      [['Nhập mã SP', 'build.svg', method(:entry)], ['Quét chọn', 'scan.svg', method(:start_scan)],
       ['Quản lý', 'manage.svg', method(:manager)]].each do |label, icon, callback|
        command = UI::Command.new(label) { callback.call }
        command.tooltip = "MH CAD2Module — #{label}"
        command.small_icon = command.large_icon = File.join(Settings::ROOT, 'ui', icon)
        @toolbar.add_item(command)
      end
      @toolbar.restore
    end

    install
  end
end
