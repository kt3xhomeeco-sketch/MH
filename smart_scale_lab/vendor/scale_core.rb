# encoding: UTF-8
#
# SmartScale::Core -- pure scaling math, independent of any tool/UI.
#
module SmartScale
  module Core
    AXES = [:x, :y, :z].freeze

    module_function

    # Combined world-aligned bounding box of the current selection,
    # expressed in the active drawing context coordinates.
    def selection_bounds(model)
      bb = Geom::BoundingBox.new
      model.selection.each { |e| bb.add(e.bounds) if e.respond_to?(:bounds) }
      bb
    end

    def empty_bounds?(bb)
      !bb.valid? || (bb.width == 0 && bb.height == 0 && bb.depth == 0)
    end

    # Length of the bbox along an axis (a Length in inches).
    def axis_length(bb, axis)
      case axis
      when :x then bb.width
      when :y then bb.height
      when :z then bb.depth
      end
    end

    # Anchor point that stays fixed during scaling, per anchor mode.
    #   :center -> bbox center (symmetric scaling)
    #   :min    -> bbox min corner (grows toward +axis)
    #   :max    -> bbox max corner (grows toward -axis)
    def anchor_point(bb, mode)
      case mode
      when :center then bb.center
      when :max    then bb.max
      else              bb.min
      end
    end

    # Apply a per-axis scaling about `anchor` to the selection in one undo step.
    # factors: [sx, sy, sz] (Floats). Returns true on success.
    def apply_scale(model, anchor, factors, op_name = 'SmartScale')
      sx, sy, sz = factors
      return false if [sx, sy, sz].any? { |f| f.nil? || !f.finite? || f == 0 }

      tr = Geom::Transformation.scaling(anchor, sx, sy, sz)
      ents = model.active_entities
      targets = model.selection.to_a
      return false if targets.empty?

      model.start_operation(op_name, true)
      ents.transform_entities(tr, targets)
      model.commit_operation
      true
    rescue => e
      model.abort_operation rescue nil
      warn "SmartScale apply_scale failed: #{e.class}: #{e.message}"
      false
    end

    # Scale the selection so its bbox length along `axis` becomes `target_len`
    # (a Length / Float in inches).
    #   uniform: same factor on all axes (except locked ones, which stay 1.0).
    #   locked:  axes that must not change (only meaningful when uniform).
    def set_axis_length(model, axis, target_len, anchor_mode: :min, uniform: false, locked: [])
      bb = selection_bounds(model)
      return false if empty_bounds?(bb)

      cur = axis_length(bb, axis)
      return false if cur.nil? || cur <= 0

      factor = target_len.to_f / cur.to_f
      return false unless factor.finite? && factor > 0

      anchor = anchor_point(bb, anchor_mode)
      factors =
        if uniform
          AXES.map { |a| (a == axis || !locked.include?(a)) ? factor : 1.0 }
        else
          axis_factors(axis, factor)
        end
      apply_scale(model, anchor, factors)
    end

    # [sx, sy, sz] with `factor` on `axis` and 1.0 on the others.
    def axis_factors(axis, factor)
      AXES.map { |a| a == axis ? factor : 1.0 }
    end

    # Parse VCB input into a Length (inches), or nil.
    # Accepts a SketchUp length ("600", "600mm", "2'6\"") OR an arithmetic
    # expression of unitless numbers in the model's display unit ("100+50",
    # "1200/2", "(300+100)*2").
    def parse_length(text)
      s = text.to_s.strip
      return nil if s.empty?
      # plain length first (handles units, feet/inches) -- skip when the text
      # is clearly an arithmetic expression so we don't raise needlessly.
      has_math = s =~ %r{[+*/]} || s =~ /\d\s*-\s*\d/
      unless has_math
        begin
          return s.to_l
        rescue ArgumentError
          nil
        end
      end
      # arithmetic over unitless numbers, evaluated in model units
      return nil unless s =~ %r{\A[\d\s.,+\-*/()]+\z}
      val = eval_arithmetic(s.tr(',', '.'))
      return nil if val.nil? || !val.finite?
      begin
        val.to_s.to_l        # interpret result in model units
      rescue ArgumentError
        nil
      end
    end

    # Safe +-*/ and parentheses evaluator (Float). Returns nil on bad input.
    def eval_arithmetic(str)
      tokens = str.scan(%r{\d+\.\d+|\d+|[()+\-*/]})
      return nil if tokens.empty?
      prec = { '+' => 1, '-' => 1, '*' => 2, '/' => 2 }
      out = []
      ops = []
      tokens.each do |t|
        if t =~ /\A\d/
          out << t.to_f
        elsif t == '('
          ops << t
        elsif t == ')'
          out << ops.pop while ops.any? && ops.last != '('
          return nil if ops.empty?
          ops.pop
        else
          out << ops.pop while ops.any? && ops.last != '(' && prec[ops.last] >= prec[t]
          ops << t
        end
      end
      out << ops.pop while ops.any?
      return nil if out.include?('(')

      stack = []
      out.each do |t|
        if t.is_a?(Float)
          stack << t
        else
          b = stack.pop
          a = stack.pop
          return nil if a.nil? || b.nil?
          case t
          when '+' then stack << a + b
          when '-' then stack << a - b
          when '*' then stack << a * b
          when '/' then return nil if b.zero?; stack << a / b
          end
        end
      end
      stack.length == 1 ? stack.first : nil
    end

  end
end
