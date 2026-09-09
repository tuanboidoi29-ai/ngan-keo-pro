# frozen_string_literal: true

module TT_NGAN_KEO_NHANH_V14
  extend self

  PLUGIN_NAME = 'TT - Tạo Ngăn Kéo Nhanh V14'
  @settings = {
    ray: 13.0, thickness: 17.5, height: 120.0, bottom_gap: 10.0,
    rear_gap: 30.0, bottom_thickness: 9.0, front_gap_l: 2.0,
    front_gap_r: 2.0, front_gap_t: 2.0, front_gap_b: 2.0,
    front_thickness: 17.5
  }
  @face = nil
  @hover = nil
  @preview = nil
  @dialog = nil
  @show_front = true

  def mm(value)
    value.to_f.mm
  end

  def walk_entities(entities, transformation = Geom::Transformation.new, &block)
    entities.each do |entity|
      next unless entity.valid?

      if entity.is_a?(Sketchup::Face)
        yield entity, transformation
      elsif entity.is_a?(Sketchup::Group)
        walk_entities(entity.entities, transformation * entity.transformation, &block)
      elsif entity.is_a?(Sketchup::ComponentInstance)
        walk_entities(entity.definition.entities, transformation * entity.transformation, &block)
      end
    end
  end

  def all_faces(model)
    result = []
    walk_entities(model.entities) { |face, tr| result << [face, tr] }
    result
  end

  def points(face, transformation)
    face.outer_loop.vertices.map { |vertex| vertex.position.transform(transformation) }
  end

  def normal(face, transformation)
    vertices = points(face, transformation)
    return nil if vertices.length < 3

    (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).normalize
  rescue StandardError
    nil
  end

  def axis_face?(vector, axis)
    return false unless vector

    vector.public_send(axis).abs > 0.92 && %i[x y z].reject { |item| item == axis }.all? { |item| vector.public_send(item).abs < 0.20 }
  end

  def inside?(value, first, second, tolerance = 1.mm)
    value >= [first, second].min - tolerance && value <= [first, second].max + tolerance
  end

  def detect_cavity(model, point, picked_face)
    faces = all_faces(model)
    x_planes = faces.filter_map do |face, tr|
      n = normal(face, tr)
      next unless axis_face?(n, :x)

      polygon = points(face, tr)
      next unless inside?(point.y, polygon.map(&:y).min, polygon.map(&:y).max) && inside?(point.z, polygon.map(&:z).min, polygon.map(&:z).max)

      { value: polygon.sum(&:x) / polygon.length, points: polygon }
    end
    left = x_planes.select { |plane| plane[:value] < point.x }.max_by { |plane| plane[:value] }
    right = x_planes.select { |plane| plane[:value] > point.x }.min_by { |plane| plane[:value] }
    return nil unless left && right

    z_planes = faces.filter_map do |face, tr|
      n = normal(face, tr)
      next unless axis_face?(n, :z)

      polygon = points(face, tr)
      next unless inside?(point.x, polygon.map(&:x).min, polygon.map(&:x).max) && inside?(point.y, polygon.map(&:y).min, polygon.map(&:y).max)

      { value: polygon.sum(&:z) / polygon.length }
    end
    bottom = z_planes.select { |plane| plane[:value] < point.z }.max_by { |plane| plane[:value] }
    top = z_planes.select { |plane| plane[:value] > point.z }.min_by { |plane| plane[:value] }

    front = nil
    if picked_face
      picked = faces.find { |face, _tr| face == picked_face }
      if picked && axis_face?(normal(*picked), :y)
        polygon = points(*picked)
        front = polygon.sum(&:y) / polygon.length
      end
    end
    front ||= [left, right].flat_map { |plane| plane[:points].map(&:y) }.min
    rear = [left, right].flat_map { |plane| plane[:points].map(&:y) }.max
    rear = nil if rear <= front + 20.mm

    {
      left: left[:value], right: right[:value], bottom: bottom && bottom[:value],
      top: top && top[:value], front: front, rear: rear
    }
  end

  def calculate(cavity)
    return nil unless cavity

    s = @settings
    left = cavity[:left] + mm(s[:ray])
    right = cavity[:right] - mm(s[:ray])
    width = right - left
    return nil if width <= mm(s[:thickness]) * 2

    bottom = (cavity[:bottom] || 0) + mm(s[:bottom_gap])
    available_height = cavity[:top] ? cavity[:top] - bottom : mm(s[:height])
    wall_height = [mm(s[:height]), available_height - mm(s[:front_gap_t])].min
    return nil if wall_height <= 0

    front = cavity[:front]
    rear = cavity[:rear] || front + 500.mm
    depth = rear - front - mm(s[:rear_gap]) - mm(s[:front_thickness])
    return nil if depth <= 20.mm

    wall_bottom = bottom + mm(s[:bottom_thickness])
    {
      cavity: cavity, left: left, right: right, width: width,
      front: front, body_front: front + mm(s[:front_thickness]),
      body_rear: front + mm(s[:front_thickness]) + depth,
      bottom: bottom, wall_bottom: wall_bottom, wall_top: wall_bottom + wall_height,
      wall_height: wall_height, thickness: mm(s[:thickness]),
      bottom_thickness: mm(s[:bottom_thickness]), front_left: cavity[:left] + mm(s[:front_gap_l]),
      front_right: cavity[:right] - mm(s[:front_gap_r]), front_bottom: bottom + mm(s[:front_gap_b]),
      front_top: cavity[:top] ? cavity[:top] - mm(s[:front_gap_t]) : wall_bottom + wall_height,
      front_thickness: mm(s[:front_thickness])
    }
  end

  def box_points(x1, x2, y1, y2, z1, z2)
    [Geom::Point3d.new(x1, y1, z1), Geom::Point3d.new(x2, y1, z1), Geom::Point3d.new(x2, y2, z1), Geom::Point3d.new(x1, y2, z1)]
  end

  def add_box(entities, x1, x2, y1, y2, z1, z2, material)
    face = entities.add_face(box_points(x1, x2, y1, y2, z1, z2))
    return unless face

    face.reverse! if face.normal.z.negative?
    face.pushpull(z2 - z1)
    entities.grep(Sketchup::Face).last(6).each { |item| item.material = material }
  end

  def create_drawer(model, data)
    model.start_operation('TT - Tạo Ngăn Kéo Nhanh V14', true)
    parent = model.entities.add_group
    parent.name = 'TT_NGAN_KEO'
    root = parent.entities
    body = model.materials['TT_NGAN_KEO_BODY'] || model.materials.add('TT_NGAN_KEO_BODY')
    body.color = Sketchup::Color.new(235, 135, 25)
    front_material = model.materials['TT_NGAN_KEO_FRONT'] || model.materials.add('TT_NGAN_KEO_FRONT')
    front_material.color = Sketchup::Color.new(255, 120, 0)

    add_box(root, data[:left], data[:left] + data[:thickness], data[:body_front], data[:body_rear], data[:wall_bottom], data[:wall_top], body)
    add_box(root, data[:right] - data[:thickness], data[:right], data[:body_front], data[:body_rear], data[:wall_bottom], data[:wall_top], body)
    add_box(root, data[:left] + data[:thickness], data[:right] - data[:thickness], data[:body_front], data[:body_front] + data[:thickness], data[:wall_bottom], data[:wall_top], body)
    add_box(root, data[:left] + data[:thickness], data[:right] - data[:thickness], data[:body_rear] - data[:thickness], data[:body_rear], data[:wall_bottom], data[:wall_top], body)
    add_box(root, data[:left], data[:right], data[:body_front], data[:body_rear], data[:bottom], data[:bottom] + data[:bottom_thickness], body)
    add_box(root, data[:front_left], data[:front_right], data[:front], data[:front] + data[:front_thickness], data[:front_bottom], data[:front_top], front_material) if @show_front
    parent.set_attribute('TT_NGAN_KEO', 'version', 'V14')
    parent.set_attribute('TT_NGAN_KEO', 'width_mm', data[:width].to_mm)
    parent.set_attribute('TT_NGAN_KEO', 'depth_mm', (data[:body_rear] - data[:body_front]).abs.to_mm)
    model.selection.clear
    model.selection.add(parent)
    model.commit_operation
    parent
  rescue StandardError => error
    model.abort_operation
    UI.messagebox("Lỗi tạo ngăn kéo: #{error.message}")
    nil
  end

  def settings_html
    <<~HTML
      <!doctype html><html lang="vi"><meta charset="utf-8"><style>body{font:13px Arial;background:#202020;color:#eee;padding:16px}.row{display:flex;justify-content:space-between;margin:8px 0}input{width:80px;background:#333;color:#fff;border:1px solid #666;padding:5px}.btn{width:100%;margin-top:12px;padding:9px;border:0;background:#ff8a00;font-weight:bold}</style><h3>Cài đặt ngăn kéo V14</h3>
      #{ @settings.map { |key, value| "<div class='row'><label>#{key}</label><input id='#{key}' value='#{value}'></div>" }.join }
      <button class="btn" onclick="save()">CẬP NHẬT PREVIEW</button><script>function save(){var d={};#{@settings.keys.map { |key| "d['#{key}']=parseFloat(document.getElementById('#{key}').value)||0;" }.join}sketchup.update(JSON.stringify(d))}</script></html>
    HTML
  end

  def open_settings
    return @dialog.bring_to_front if @dialog && @dialog.visible?

    @dialog = UI::HtmlDialog.new(dialog_title: PLUGIN_NAME, preferences_key: 'tt_ngan_keo_v14', width: 390, height: 570, resizable: false)
    @dialog.set_html(settings_html)
    @dialog.add_action_callback('update') do |_context, payload|
      values = JSON.parse(payload)
      values.each { |key, value| @settings[key.to_sym] = value.to_f }
      refresh_preview(Sketchup.active_model, @hover, @face) if @hover
      Sketchup.active_model.active_view.invalidate
    end
    @dialog.set_on_closed { @dialog = nil }
    @dialog.show
  end

  def refresh_preview(model, point, face)
    @hover = point
    @face = face
    @preview = calculate(detect_cavity(model, point, face))
    Sketchup.set_status_text(@preview ? "VIEW: Rộng #{@preview[:width].to_mm.round(1)} mm | Di chuột đúng khoang rồi click để tạo" : 'TT: Không đủ hình học để nhận diện khoang.')
    model.active_view.invalidate
  rescue StandardError => error
    @preview = nil
    Sketchup.set_status_text("TT: #{error.message}")
  end

  def draw_box_preview(view, data, x1, x2, y1, y2, z1, z2)
    points = box_points(x1, x2, y1, y2, z1, z2)
    view.drawing_color = Sketchup::Color.new(255, 120, 0, 100)
    view.draw(GL_QUADS, [points[0], points[1], points[2], points[3]])
    view.drawing_color = Sketchup::Color.new(255, 95, 0, 255)
    view.draw(GL_LINE_LOOP, points)
  end

  def draw_preview(view)
    return unless @preview

    data = @preview
    draw_box_preview(view, data, data[:left], data[:left] + data[:thickness], data[:body_front], data[:body_rear], data[:wall_bottom], data[:wall_top])
    draw_box_preview(view, data, data[:right] - data[:thickness], data[:right], data[:body_front], data[:body_rear], data[:wall_bottom], data[:wall_top])
    draw_box_preview(view, data, data[:front_left], data[:front_right], data[:front], data[:front] + data[:front_thickness], data[:front_bottom], data[:front_top]) if @show_front
  end

  def toggle_front
    @show_front = !@show_front
    Sketchup.active_model.active_view.invalidate
  end

  class Tool
    def activate
      Sketchup.set_status_text('Di chuột vào mặt khoang tủ. TAB: cài đặt. SHIFT: bật/tắt mặt. Click trái: tạo.')
    end

    def deactivate(view)
      view.invalidate
    end

    def onMouseMove(_flags, x, y, view)
      input = Sketchup::InputPoint.new
      input.pick(view, x, y)
      if input.valid? && input.face
        TT_NGAN_KEO_NHANH_V14.refresh_preview(Sketchup.active_model, input.position, input.face)
      else
        TT_NGAN_KEO_NHANH_V14.instance_variable_set(:@preview, nil)
        view.invalidate
      end
    end

    def onKeyDown(key, _repeat, _flags, _view)
      TT_NGAN_KEO_NHANH_V14.open_settings if key == 9
      TT_NGAN_KEO_NHANH_V14.toggle_front if key == 16
    end

    def onLButtonDown(_flags, _x, _y, view)
      data = TT_NGAN_KEO_NHANH_V14.instance_variable_get(:@preview)
      if data
        TT_NGAN_KEO_NHANH_V14.create_drawer(Sketchup.active_model, data)
      else
        UI.messagebox('Chưa nhận diện được khoang tủ. Hãy di chuột lên mặt khoang.')
      end
      view.invalidate
    end

    def draw(view)
      TT_NGAN_KEO_NHANH_V14.draw_preview(view)
    end
  end

  def start
    Sketchup.active_model.select_tool(TT_NGAN_KEO_NHANH_V14::Tool.new)
  end
end