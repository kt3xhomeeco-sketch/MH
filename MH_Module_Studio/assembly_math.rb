# encoding: UTF-8
module MH
  module ModuleStudio
    # Assembly geometry is independent of the ATT solver inside a module.
    module AssemblyMath
      extend self
      MODES = %w[contact center fit angle repeat].freeze
      DIRECTIONS = { 'right' => [1, 0, 0], 'left' => [-1, 0, 0],
                     'up' => [0, 0, 1], 'down' => [0, 0, -1] }.freeze

      def dot(a, b)
        a.zip(b).sum { |x, y| x * y }
      end

      def add(a, b)
        a.zip(b).map { |x, y| x + y }
      end

      def sub(a, b)
        a.zip(b).map { |x, y| x - y }
      end

      def mul(a, value)
        a.map { |x| x * value }
      end

      def unit(vector)
        length = Math.sqrt(dot(vector, vector))
        raise Core::Error, 'Phương liên kết không hợp lệ.' unless length.finite? && length > 1.0e-9
        mul(vector, 1.0 / length)
      end

      def cross(a, b)
        [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
      end

      def parallel!(a, b)
        raise Core::Error, 'Hai mặt giới hạn phải song song.' if dot(unit(a), unit(b)).abs < 0.999999
      end

      def offset(a, b, distance)
        parallel!(a['normal'], b['normal'])
        normal = unit(a['normal'])
        mul(normal, Core.number(distance) - dot(sub(b['point'], a['point']), normal))
      end

      def interval(a, c, normal = a['normal'])
        parallel!(a['normal'], c['normal'])
        parallel!(a['normal'], normal)
        [dot(a['point'], normal), dot(c['point'], normal)].sort
      end

      def centered(a, c, bounds, clearance: nil)
        normal = unit(a['normal'])
        low, high = interval(a, c, normal)
        span = high - low
        raise Core::Error, 'Khoang không có chiều rộng.' if span <= 0.01
        target = clearance.nil? ? bounds[1] - bounds[0] : span - 2 * Core.number(clearance)
        raise Core::Error, 'Kích thước không vừa khoang; giảm khe hở.' if target <= 0.01 || target > span + 0.01
        { 'size' => target, 'delta' => (low + high - bounds.sum) * 0.5 }
      end

      # Coordinates are minimum planes along the chosen (possibly negative) axis.
      def repeat_layout(count:, size:, start:, gap:, interval: nil, ends: true)
        number = Core.number(count)
        raise Core::Error, 'Số lượng phải là số nguyên từ 1 đến 100.' unless number == number.to_i && number.between?(1, 100)
        count = number.to_i
        size = Core.number(size)
        raise Core::Error, 'Module không có kích thước theo phương lặp.' unless size > 0.01
        gap = Core.number(gap)
        origin = Core.number(start)
        if interval
          low, high = interval.sort
          slots = ends ? count + 1 : count - 1
          gap = slots.zero? ? 0.0 : (high - low - count * size) / slots
          raise Core::Error, 'Không đủ khoảng lọt lòng để chia đều.' if gap < -0.01 || high - low < count * size - 0.01
          gap = [gap, 0.0].max
          origin = count == 1 && !ends ? (low + high - size) * 0.5 : low + (ends ? gap : 0)
        else
          raise Core::Error, 'Khoảng hở khi lặp phải từ 0 mm.' if gap.negative?
        end
        { 'gap' => gap, 'positions' => count.times.map { |index| origin + index * (size + gap) } }
      end

      def rotation(a, b, degrees)
        angle = Core.number(degrees)
        raise Core::Error, 'Góc phải trong khoảng 0–180°.' unless angle.between?(0, 180)
        an = unit(a); bn = unit(b)
        current = Math.acos([[dot(an, bn), -1.0].max, 1.0].min)
        axis = cross(bn, an)
        axis = cross(bn, bn[0].abs < 0.8 ? [1, 0, 0] : [0, 1, 0]) if dot(axis, axis) < 1.0e-12
        { 'axis' => unit(axis), 'radians' => current - angle * Math::PI / 180.0 }
      end

      # Remove only motion forbidden by existing plane relations. Independent
      # tangential directions remain available, including oblique face planes.
      def allowed_motion(delta, normals)
        basis = []
        normals.each do |normal|
          vector = unit(normal)
          basis.each { |prior| vector = sub(vector, mul(prior, dot(vector, prior))) }
          basis << unit(vector) if dot(vector, vector) > 1.0e-12
        end
        basis.reduce(delta.dup) { |motion, normal| sub(motion, mul(normal, dot(motion, normal))) }
      end

      def same_surface?(a, b)
        return false unless a && b
        fields = %w[scope root axis side]
        return false unless fields.all? { |key| a[key]==b[key] }
        if a['part'] || b['part']
          a['part']==b['part']
        elsif a['panel'] || b['panel']
          a['panel']==b['panel']
        else
          a.fetch('path',[])==b.fetch('path',[])
        end
      end

      def ordered(records)
        producers = records.each_with_object({}) do |record, result|
          record.fetch('copies', []).each { |pid| result[[record['scope'],pid]] = root_identity(record['b']) }
        end
        incoming = {}
        records.each do |record|
          target = root_identity(record.fetch('b'))
          raise Core::Error, 'Bản lặp được điều khiển bởi module gốc; chọn module gốc để sửa.' if producers.key?(target)
          refs = %w[a c r1 r2].filter_map { |key| root_identity(record[key]) if record[key] }.map { |id| producers.fetch(id, id) }.uniq
          raise Core::Error, 'Mặt tham chiếu phải thuộc module khác B.' if refs.include?(target)
          incoming[target] ||= []
          incoming[target] |= refs
        end
        result = []
        until incoming.empty?
          roots = incoming.keys.select { |id| incoming[id].none? { |ref| incoming.key?(ref) } }
          raise Core::Error, 'Liên kết tạo vòng phụ thuộc giữa các module.' if roots.empty?
          roots.each do |id|
            result.concat(records.select { |record| root_identity(record['b']) == id })
            incoming.delete(id)
          end
        end
        result
      end

      def root_identity(anchor)
        [anchor['scope'],anchor.fetch('root')]
      end

      def contact_solution(rows, responses = [])
        baseline = 3.times.to_h { |axis| ["p#{axis}",0.0] }
        responses.each_index { |index| baseline["s#{index}"] = 0.0 }
        equations = rows.each_with_index.map do |row,index|
          terms = row.fetch('normal').each_with_index.to_h { |value,axis| ["p#{axis}",value] }
          responses.each_with_index { |values,axis| terms["s#{axis}"] = values.fetch(index) }
          [terms,row.fetch('delta'),row.fetch('name','mặt tiếp xúc')]
        end
        values = PlaneSolver.solve(equations,baseline)
        { 'move'=>3.times.map { |axis| values.fetch("p#{axis}") },
          'sizes'=>responses.each_index.map { |axis| values.fetch("s#{axis}") } }
      end

      # Distribute aggregate-size error over measured dimension freedoms.
      # Relative size weights avoid assigning the whole correction to one of
      # several equal-sized modules. Fixed/fully constrained axes have response 0.
      class NoEnvelopeFreedom < Core::Error; end

      def envelope_correction(error,responses,sizes)
        error = Core.number(error)
        unless responses.is_a?(Array) && sizes.is_a?(Array) && responses.length==sizes.length &&
               sizes.all? { |size| Core.number(size)>0 }
          raise Core::Error,'Dữ liệu hiệu chỉnh phủ bì cụm không hợp lệ.'
        end
        responses = responses.map { |response| Core.number(response) }
        weights = sizes.map { |size| Core.number(size) }
        divisor = responses.zip(weights).sum { |response,size| response*response*size }
        raise NoEnvelopeFreedom,'Không còn kích thước tự do để giữ phủ bì cụm.' if divisor<=1.0e-10
        changes = responses.zip(weights).map { |response,size| error*response*size/divisor }
        unless weights.zip(changes).all? { |size,change| (size+change)>0.01 }
          raise NoEnvelopeFreedom,'Phủ bì yêu cầu nhỏ hơn kích thước cho phép của các module.'
        end
        changes
      end
    end
  end
end
