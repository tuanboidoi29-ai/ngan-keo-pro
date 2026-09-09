# frozen_string_literal: true

module TT
  module NganKeo
    class VectorBoardTool
      def initialize(thickness_mm, gap_left, gap_right, gap_top, gap_bottom)
        @thickness = thickness_mm.mm
        @thickness_mm = thickness_mm
        @gap_left = gap_left.mm
        @gap_right = gap_right.mm
        @gap_top = gap_top.mm
        @gap_bottom = gap_bottom.mm
        @start_point = nil
        @current_point = nil
        @forced_orientation = nil
        @flip_direction = 1
      end

      def activate
        Sketchup.set_status_text('Điểm 1 -> kéo chuột -> điểm 2. SHIFT: đảo hướng ván.')
      end

      def deactivate(view)
        view.invalidate
      end

      def getExtents
        bounds = Sketchup.active_model.bounds
        bounds.add(@start_point) if @start_point
        bounds.add(@current_point) if @current_point
        bounds
      end

      def onKeyDown(key, _repeat, _flags, view)
        case key
        when VK_UP then @forced_orientation = 0
        when VK_LEFT then @forced_orientation = 1
        when VK_RIGHT then @forced_orientation = 2
        when VK_DOWN then @forced_orientation = nil
        when VK_SHIFT
          @flip_direction *= -1
          direction = @flip_direction == 1 ? 'NGOÀI' : 'TRONG'
          Sketchup.set_status_text("Hướng ván: #{direction}")
        end
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        input = Sketchup::InputPoint.new
        input.pick(view, x, y)
        @current_point = input.position if input.valid?
        view.invalidate
      end

      def onCancel(_reason, view)
        @start_point = nil
        @current_point = nil
        view.invalidate
        activate
      end

      def onLButtonDown(_flags, x, y, view)
        input = Sketchup::InputPoint.new
        input.pick(view, x, y)
        return unless input.valid?

        if @start_point.nil?
          @start_point = input.position
          Sketchup.set_status_text('Kéo chọn kích thước. SHIFT đảo hướng. Click lần 2 để chốt.')
          return
        end

        finish_board(input.position)
        @start_point = nil
        @current_point = nil
        activate
        view.invalidate
      end

      def draw(view)
        return unless @current_point

        unless @start_point
          view.draw_points([@current_point], 6, 3, 'black')
          return
        end

        orientation = orientation_for(@start_point, @current_point)
        points = calculate_points(@start_point, @current_point, orientation)
        return if points.empty?

        color = %w[blue green red][orientation]
        view.drawing_color = color
        view.line_width = 2
        view.line_stipple = '-'
        view.draw(GL_LINE_LOOP, points[0, 4])
        view.draw(GL_LINE_LOOP, points[4, 4])
        view.draw(GL_LINES, [points[0], points[4], points[1], points[5], points[2], points[6], points[3], points[7]])
      end

      private

      def orientation_for(first, second)
        return @forced_orientation unless @forced_orientation.nil?

        dx = (second.x - first.x).abs
        dy = (second.y - first.y).abs
        dz = (second.z - first.z).abs
        return 1 if dz > dx && dz > dy && dx > dy
        return 2 if dz > dx && dz > dy

        0
      end

      def calculate_points(first, second, orientation)
        thickness = @thickness * @flip_direction
        case orientation
        when 0
          sign_x = second.x >= first.x ? 1 : -1
          sign_y = second.y >= first.y ? 1 : -1
          x1 = first.x + @gap_left * sign_x
          x2 = second.x - @gap_right * sign_x
          y1 = first.y + @gap_bottom * sign_y
          y2 = second.y - @gap_top * sign_y
          corners = [Geom::Point3d.new(x1, y1, first.z), Geom::Point3d.new(x2, y1, first.z), Geom::Point3d.new(x2, y2, first.z), Geom::Point3d.new(x1, y2, first.z)]
          push = Geom::Vector3d.new(0, 0, thickness)
        when 1
          sign_x = second.x >= first.x ? 1 : -1
          sign_z = second.z >= first.z ? 1 : -1
          x1 = first.x + @gap_left * sign_x
          x2 = second.x - @gap_right * sign_x
          z1 = first.z + @gap_bottom * sign_z
          z2 = second.z - @gap_top * sign_z
          corners = [Geom::Point3d.new(x1, first.y, z1), Geom::Point3d.new(x2, first.y, z1), Geom::Point3d.new(x2, first.y, z2), Geom::Point3d.new(x1, first.y, z2)]
          push = Geom::Vector3d.new(0, thickness, 0)
        else
          sign_y = second.y >= first.y ? 1 : -1
          sign_z = second.z >= first.z ? 1 : -1
          y1 = first.y + @gap_left * sign_y
          y2 = second.y - @gap_right * sign_y
          z1 = first.z + @gap_bottom * sign_z
          z2 = second.z - @gap_top * sign_z
          corners = [Geom::Point3d.new(first.x, y1, z1), Geom::Point3d.new(first.x, y2, z1), Geom::Point3d.new(first.x, y2, z2), Geom::Point3d.new(first.x, y1, z2)]
          push = Geom::Vector3d.new(thickness, 0, 0)
        end
        corners + corners.map { |point| point + push }
      end

      def finish_board(end_point)
        return if @start_point == end_point

        model = Sketchup.active_model
        points = calculate_points(@start_point, end_point, orientation_for(@start_point, end_point))
        return if points.empty? || points[0].distance(points[1]) < 1.mm || points[0].distance(points[3]) < 1.mm

        model.start_operation('Tạo ván có khoảng hở', true)
        begin
          group = model.active_entities.add_group
          face = group.entities.add_face(points[0, 4])
          if face
            normal = [Geom::Vector3d.new(0, 0, 1), Geom::Vector3d.new(0, 1, 0), Geom::Vector3d.new(1, 0, 0)][orientation_for(@start_point, end_point)]
            face.reverse! if face.normal.dot(normal) < 0
            face.reverse! if @flip_direction.negative?
            face.pushpull(@thickness)
          end
          width = [points[0].distance(points[1]), points[0].distance(points[3])].map(&:to_mm).max.round
          height = [points[0].distance(points[1]), points[0].distance(points[3])].map(&:to_mm).min.round
          group.name = "Ván #{width}x#{height}x#{@thickness_mm.round}"
          tag = "Ván #{@thickness_mm.round}mm"
          group.layer = model.layers[tag] || model.layers.add(tag)
          model.selection.clear
          model.selection.add(group)
          model.commit_operation
        rescue StandardError => error
          model.abort_operation
          UI.messagebox("Không thể tạo ván: #{error.message}")
        end
      end
    end
  end
end