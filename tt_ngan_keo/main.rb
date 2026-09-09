# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require_relative 'board_tool'

module TT
  module NganKeo
    VERSION = '1.2.0'
    CREATOR = 'TRẦN TUẤN'
    RELEASE_URL = 'https://github.com/tuanboidoi29-ai/ngan-keo-pro/releases'
    UPDATE_MANIFEST_URL = 'https://raw.githubusercontent.com/tuanboidoi29-ai/ngan-keo-pro/main/update.json'
    PLUGIN_DIR = File.dirname(__FILE__)
    ICON_PATH = File.join(PLUGIN_DIR, 'icons', 'ngan_keo.svg')
    CREATE_ICON_PATH = File.join(PLUGIN_DIR, 'icons', 'create_drawer.svg')
    UPDATE_ICON_PATH = File.join(PLUGIN_DIR, 'icons', 'update.svg')

    @dialog = nil
    @settings_dialog = nil
    @drawers = []
    @drawer_settings = {
      width: 600.0,
      height: 400.0,
      depth: 300.0,
      thickness: 18.0,
      bottom_thickness: 12.0
    }

    module_function

    def command
      return @command if @command

      @command = UI::Command.new('TT - ngan keo') { show_dialog }
      @command.tooltip = 'Mở TT - ngan keo'
      @command.status_bar_text = 'Quản lý ngăn kéo'
      @command.menu_text = 'TT - ngan keo'
      @command.set_validation_proc { MF_ENABLED }
      set_command_icon(@command)
      @command
    end

    def update_command
      return @update_command if @update_command

      @update_command = UI::Command.new('Kiểm tra bản cập nhật TT - ngan keo') { check_for_updates }
      @update_command.tooltip = 'Kiểm tra phiên bản mới'
      @update_command.set_validation_proc { MF_ENABLED }
      set_command_icon(@update_command, UPDATE_ICON_PATH)
      @update_command
    end

    def create_command
      return @create_command if @create_command

      @create_command = UI::Command.new('Tạo ngăn kéo theo chuột') { activate_drawer_tool }
      @create_command.tooltip = 'Chọn 3 góc và kéo sâu để tạo ngăn kéo'
      @create_command.status_bar_text = 'Chọn góc 1 của vùng tạo ngăn kéo'
      set_command_icon(@create_command, CREATE_ICON_PATH)
      @create_command
    end

    def board_command
      return @board_command if @board_command

      @board_command = UI::Command.new('Vẽ ván có khoảng hở') { create_smart_board }
      @board_command.tooltip = 'Vẽ tấm ván theo 2 điểm và khoảng hở'
      @board_command.status_bar_text = 'Nhập thông số ván rồi chọn 2 điểm'
      set_command_icon(@board_command, CREATE_ICON_PATH)
      @board_command
    end

    def create_smart_board
      prompts = ['Độ dày ván (mm):', 'Hở trái (mm):', 'Hở phải (mm):', 'Hở trên (mm):', 'Hở dưới (mm):']
      defaults = [18.0, 0.0, 0.0, 0.0, 0.0]
      values = UI.inputbox(prompts, defaults, 'Cấu hình ván thông minh')
      return unless values

      Sketchup.active_model.select_tool(
        VectorBoardTool.new(*values.map(&:to_f))
      )
    end

    def activate_drawer_tool
      Sketchup.active_model.select_tool(DrawerTool.new)
    end

    def drawer_settings
      @drawer_settings
    end

    def show_settings_dialog
      if @settings_dialog && @settings_dialog.visible?
        @settings_dialog.bring_to_front
        return
      end

      @settings_dialog = UI::HtmlDialog.new(
        dialog_title: 'Cài đặt ngăn kéo',
        preferences_key: 'tt_ngan_keo_settings',
        scrollable: false,
        resizable: false,
        width: 390,
        height: 440,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @settings_dialog.set_html(settings_html)
      @settings_dialog.add_action_callback('save_settings') do |_context, payload|
        values = JSON.parse(payload)
        @drawer_settings = {
          width: values['width'].to_f,
          height: values['height'].to_f,
          depth: values['depth'].to_f,
          thickness: values['thickness'].to_f,
          bottom_thickness: values['bottom_thickness'].to_f
        }
        @settings_dialog.close
      end
      @settings_dialog.add_action_callback('cancel') { @settings_dialog.close }
      @settings_dialog.set_on_closed { @settings_dialog = nil }
      @settings_dialog.show
    end

    def show_dialog
      load_drawers
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: 'TT - ngan keo',
        preferences_key: 'tt_ngan_keo',
        scrollable: true,
        resizable: true,
        width: 720,
        height: 560,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(dialog_html)
      bind_dialog_callbacks
      @dialog.set_on_closed { @dialog = nil }
      @dialog.show
    end

    def schedule_update_check
      last_check = Sketchup.read_default('TT - ngan keo', 'last_update_check', 0).to_i
      return if last_check > Time.now.to_i - 86_400

      Sketchup.write_default('TT - ngan keo', 'last_update_check', Time.now.to_i)
      UI.start_timer(3.0, false) { check_for_updates(silent: true) }
    end

    def check_for_updates(silent: false)
      unless defined?(Sketchup::Http::Request)
        open_release_page unless silent
        return
      end

      request = Sketchup::Http::Request.new(UPDATE_MANIFEST_URL)
      request.start do |_http_request, response|
        if response.status_code.to_i != 200
          open_release_page('Không thể kiểm tra cập nhật.') unless silent
          next
        end

        manifest = JSON.parse(response.body)
        latest = manifest['version'].to_s
        if newer_version?(latest, VERSION)
          message = "Có bản cập nhật v#{latest} cho TT - ngan keo.\n\nTải và cài đặt ngay?"
          download_update(manifest['rbz_url'].to_s) if UI.messagebox(message) == IDYES
        elsif !silent
          UI.messagebox("TT - ngan keo đang ở phiên bản mới nhất v#{VERSION}.")
        end
      rescue JSON::ParserError
        open_release_page('Manifest cập nhật không hợp lệ.') unless silent
      end
    rescue StandardError => error
      open_release_page("Không thể kiểm tra cập nhật: #{error.message}") unless silent
    end

    def newer_version?(remote, current)
      remote.split('.').map(&:to_i) > current.split('.').map(&:to_i)
    end

    def download_update(url)
      return open_release_page('Link cập nhật không hợp lệ.') if url.empty?

      request = Sketchup::Http::Request.new(url)
      request.start do |_http_request, response|
        unless response.status_code.to_i == 200
          open_release_page('Không thể tải file cập nhật.')
          next
        end

        archive = File.join(Sketchup.temp_dir, 'TT-ngan-keo-update.rbz')
        File.binwrite(archive, response.body)
        install_update(archive)
      end
    rescue StandardError => error
      open_release_page("Không thể tải bản cập nhật: #{error.message}")
    end

    def install_update(archive)
      unless Sketchup.respond_to?(:install_from_archive)
        UI.openURL(RELEASE_URL)
        return
      end

      installed = Sketchup.install_from_archive(archive)
      if installed
        UI.start_timer(0.5, false) do
          reload_runtime
          UI.messagebox('Đã cập nhật và nạp phiên bản mới. Không cần khởi động lại SketchUp.')
        end
      else
        UI.messagebox('SketchUp đã hủy cài đặt hoặc không thể cài file RBZ.')
      end
    rescue StandardError => error
      UI.messagebox("Không thể cài bản cập nhật: #{error.message}\n\nBạn có thể cài thủ công từ trang phát hành.")
      UI.openURL(RELEASE_URL)
    end

    def reload_runtime
      @dialog.close if @dialog && @dialog.visible?
      @settings_dialog.close if @settings_dialog && @settings_dialog.visible?
      Sketchup.active_model.select_tool(nil)

      %i[VERSION CREATOR RELEASE_URL UPDATE_MANIFEST_URL PLUGIN_DIR ICON_PATH CREATE_ICON_PATH UPDATE_ICON_PATH].each do |name|
        remove_const(name) if const_defined?(name, false)
      end
      remove_const(:DrawerTool) if const_defined?(:DrawerTool, false)
      load(__FILE__)
    rescue StandardError => error
      UI.messagebox("Đã cài bản mới nhưng không thể nạp nóng: #{error.message}\nVui lòng khởi động lại SketchUp.")
    end

    def open_release_page(reason = nil)
      message = [reason, 'Mở trang phát hành để kiểm tra thủ công?'].compact.join("\n\n")
      UI.messagebox(message) == IDYES && UI.openURL(RELEASE_URL)
    end

    def bind_dialog_callbacks
      @dialog.add_action_callback('save_drawer') do |_context, payload|
        data = JSON.parse(payload)
        @drawers << {
          'name' => data['name'].to_s.strip,
          'area' => data['area'].to_s.strip,
          'items' => data['items'].to_s.split(',').map(&:strip).reject(&:empty?),
          'updated_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S')
        }
        save_drawers
        refresh_dialog
      end
      @dialog.add_action_callback('delete_drawer') do |_context, index|
        @drawers.delete_at(index.to_i)
        save_drawers
        refresh_dialog
      end
      @dialog.add_action_callback('check_updates') { check_for_updates }
    end

    def refresh_dialog
      @dialog.execute_script("window.renderDrawers(#{JSON.generate(@drawers)})") if @dialog
    end

    def set_command_icon(ui_command, icon_path = ICON_PATH)
      return unless File.exist?(icon_path)

      ui_command.small_icon = icon_path
      ui_command.large_icon = icon_path
    end

    def data_path
      File.join(Sketchup.temp_dir, 'tt_ngan_keo.json')
    end

    def load_drawers
      @drawers = JSON.parse(File.read(data_path)) if File.exist?(data_path)
    rescue JSON::ParserError
      @drawers = []
    end

    def save_drawers
      File.write(data_path, JSON.pretty_generate(@drawers))
    end

    def dialog_html
      <<~HTML
        <!doctype html><html lang="vi"><head><meta charset="utf-8"><style>
        *{box-sizing:border-box}body{margin:0;padding:28px;background:#f7f8f3;color:#27302d;font:14px Arial,sans-serif}h1{margin:0 0 6px;font-size:24px}p{color:#748078}.top{display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:22px}.button{border:0;border-radius:7px;padding:10px 14px;color:#fff;background:#27302d;cursor:pointer}.button.alt{color:#27302d;background:#e4eee5;margin-right:8px}.form{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:22px}.form input{min-width:0;border:1px solid #dfe4dc;border-radius:6px;padding:10px;background:#fff}.form input:last-of-type{grid-column:1/-1}.cards{display:grid;grid-template-columns:repeat(2,1fr);gap:10px}.card{padding:15px;border:1px solid #e1e5de;border-radius:9px;background:#fff}.card strong{display:block;font-size:15px}.card small{display:block;margin-top:6px;color:#7c8780}.remove{float:right;border:0;color:#aa6e62;background:transparent;cursor:pointer}.empty{padding:35px;border:1px dashed #cfd7ce;border-radius:9px;text-align:center;color:#7c8780}@media(max-width:600px){.cards{grid-template-columns:1fr}.form{grid-template-columns:1fr}}
        </style></head><body><div class="top"><div><h1>TT - ngan keo</h1><p>Quản lý ngăn kéo trong mô hình SketchUp. v#{VERSION}</p></div><button class="button alt" onclick="sketchup.check_updates()">Kiểm tra cập nhật</button></div><div class="form"><input id="name" placeholder="Tên ngăn kéo"><input id="area" placeholder="Khu vực"><input id="items" placeholder="Vật dụng, phân cách bằng dấu phẩy"><button class="button" onclick="save()">+ Thêm ngăn kéo</button></div><div id="cards" class="cards"></div><script>window.sketchup=window.sketchup||{};function save(){var n=document.getElementById('name'),a=document.getElementById('area'),i=document.getElementById('items');if(!n.value.trim()||!a.value.trim()){alert('Vui lòng nhập tên và khu vực');return}sketchup.save_drawer(JSON.stringify({name:n.value,area:a.value,items:i.value}));n.value='';a.value='';i.value=''}window.renderDrawers=function(ds){var c=document.getElementById('cards');c.innerHTML=ds.length?ds.map(function(d,i){return '<div class="card"><button class="remove" onclick="sketchup.delete_drawer('+i+')">Xóa</button><strong>'+d.name+'</strong><small>'+d.area+' · '+(d.items.length?d.items.join(', '):'chưa có vật dụng')+'</small></div>'}).join(''):'<div class="empty">Chưa có ngăn kéo nào.</div>'};
        </script></body></html>
      HTML
    end

    def settings_html
      values = drawer_settings
      <<~HTML
        <!doctype html><html lang="vi"><head><meta charset="utf-8"><style>
        *{box-sizing:border-box}body{margin:0;padding:24px;background:#f7f8f3;color:#27302d;font:14px Arial,sans-serif}h1{margin:0 0 7px;font-size:22px}p{margin:0 0 20px;color:#748078;font-size:12px}.field{display:flex;align-items:center;justify-content:space-between;margin:12px 0}.field label{font-weight:600}.field input{width:110px;padding:9px;border:1px solid #dfe4dc;border-radius:6px;text-align:right}.unit{margin-left:-28px;margin-right:10px;color:#879188}.actions{display:flex;justify-content:flex-end;gap:8px;margin-top:24px}.button{border:0;border-radius:7px;padding:10px 15px;cursor:pointer}.save{color:#fff;background:#27302d}.cancel{color:#27302d;background:#e4eee5}
        </style></head><body><h1>Cài đặt ngăn kéo</h1><p>Nhấn TAB để mở bảng này bất cứ lúc nào trong công cụ tạo ngăn kéo.</p><div class="field"><label>Chiều rộng</label><input id="width" type="number" min="36" value="#{values[:width]}"><span class="unit">mm</span></div><div class="field"><label>Chiều cao</label><input id="height" type="number" min="36" value="#{values[:height]}"><span class="unit">mm</span></div><div class="field"><label>Chiều sâu mặc định</label><input id="depth" type="number" min="10" value="#{values[:depth]}"><span class="unit">mm</span></div><div class="field"><label>Độ dày 4 thanh</label><input id="thickness" type="number" min="3" value="#{values[:thickness]}"><span class="unit">mm</span></div><div class="field"><label>Độ dày tấm đáy</label><input id="bottom_thickness" type="number" min="3" value="#{values[:bottom_thickness]}"><span class="unit">mm</span></div><div class="actions"><button class="button cancel" onclick="sketchup.cancel()">Hủy</button><button class="button save" onclick="save()">Lưu cài đặt</button></div><script>function save(){var ids=['width','height','depth','thickness','bottom_thickness'],data={};ids.forEach(function(id){data[id]=document.getElementById(id).value});sketchup.save_settings(JSON.stringify(data))}</script></body></html>
      HTML
    end

    class DrawerTool
      DEFAULT_DEPTH = 300.mm

      def initialize
        @points = []
        @normal = nil
        @preview = nil
        @hover_position = nil
        @detected_face = nil
      end

      def activate
        update_status
      end

      def deactivate(view)
        view.invalidate
      end

      def onCancel(_reason, view)
        @points.clear
        @preview = nil
        @detected_face = nil
        view.invalidate
        update_status
      end

      def onMouseMove(_flags, x, y, view)
        input = view.inputpoint(x, y)
        ray_face, ray_position = face_under_cursor(view, x, y)
        face = input.valid? && input.face ? input.face : ray_face
        @detected_face = rectangular_face(face)
        @hover_position = input.valid? && input.face ? input.position : ray_position
        @preview = @hover_position
        view.tooltip = tooltip_text(input)
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        return unless key == 9 || (defined?(VK_TAB) && key == VK_TAB)

        NganKeo.show_settings_dialog
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        input = view.inputpoint(x, y)
        return unless input.valid? || @hover_position

        if @points.empty?
          face = @detected_face || (input.valid? ? input.face : nil)
          @normal = face ? face.normal : view.camera.direction.reverse
          @points << (@hover_position || input.position)
          update_status
          view.invalidate
          return
        end
        @points << (@hover_position || input.position)
        if @points.length == 2
          @points = rectangle_from_diagonal(@points[0], @points[1], @detected_face, view)
          create_drawer(detect_depth(@points.first, @normal))
          onCancel(nil, view)
        else
          update_status
          view.invalidate
        end
      end

      def draw(view)
        if @detected_face && @points.empty?
          view.line_width = 1
          view.drawing_color = Sketchup::Color.new(190, 205, 198)
          view.draw(GL_LINE_LOOP, @detected_face.vertices.map(&:position))
        end

        return if @points.empty? || !@preview

        view.line_width = 2
        view.drawing_color = Sketchup::Color.new(244, 125, 100)
        if @points.length == 1
          view.draw(GL_LINE_STRIP, [@points.first, @preview])
        end
      end

      private

      def tooltip_text(input)
        return 'Di chuột vào mặt trong lòng tủ' unless input.valid? || @detected_face

        if @points.empty? && @detected_face
          width, height = face_dimensions(@detected_face)
          return "Lòng tủ: Rộng #{format_length(width)} x Cao #{format_length(height)} | Click để nhận biết"
        end

        case @points.length
        when 0 then 'Click góc thứ nhất của ngăn kéo'
        else "Click góc đối diện theo đường chéo: #{distance(@points[0], input.position)}"
        end
      end

      def update_status
        messages = [
          'Click góc thứ nhất của ngăn kéo',
          'Click góc đối diện theo đường chéo để tự tạo ngăn kéo'
        ]
        Sketchup.set_status_text(messages[[ @points.length, 1 ].min], SB_PROMPT)
      end

      def distance(first, second)
        format_length(first.distance(second))
      end

      def format_length(length)
        "#{length.to_mm.round(1)} mm"
      end

      def create_drawer(depth_value = nil)
        origin, width_end, height_end = @points
        width_vector = width_end - origin
        height_vector = height_end - origin
        configured = NganKeo.drawer_settings
        thickness = configured[:thickness].mm
        bottom_thickness = configured[:bottom_thickness].mm
        depth_value ||= configured[:depth].mm
        depth_vector = @normal.clone
        depth_vector.length = depth_value

        width = width_vector.length
        height = height_vector.length
        if width <= thickness * 2 || height <= thickness * 2
          UI.messagebox('Khoảng tạo quá nhỏ cho 4 thanh và tấm đáy.')
          return
        end

        u = width_vector.normalize
        v = height_vector.normalize
        model = Sketchup.active_model
        model.start_operation('Tạo ngăn kéo', true)
        begin
          group = model.active_entities.add_group
          entities = group.entities
          add_prism(entities, origin, u * thickness, v * height, depth_vector)
          add_prism(entities, origin + u * (width - thickness), u * thickness, v * height, depth_vector)
          add_prism(entities, origin, u * (width - thickness), v * thickness, depth_vector)
          add_prism(entities, origin + v * (height - thickness), u * (width - thickness), v * thickness, depth_vector)

          inner_origin = origin + u * thickness + v * thickness
          add_prism(entities, inner_origin, u * (width - thickness * 2), depth_vector, v * bottom_thickness)
          add_prism(entities, origin, u * width, v * height, depth_vector.reverse * thickness)
          group.name = 'TT - ngan keo'
          model.selection.clear
          model.selection.add(group)
          model.commit_operation
        rescue StandardError => error
          model.abort_operation
          UI.messagebox("Không thể tạo ngăn kéo: #{error.message}")
        end
      end

      def rectangle_from_diagonal(first, opposite, face, view)
        diagonal = opposite - first
        axes = face_axes(face, view)
        width = diagonal.dot(axes[0])
        height = diagonal.dot(axes[1])
        axes[0] = axes[0].reverse if width.negative?
        axes[1] = axes[1].reverse if height.negative?
        [first, first + axes[0] * width.abs, first + axes[1] * height.abs]
      end

      def face_axes(face, view)
        if face && face.vertices.length >= 3
          positions = face.vertices.map(&:position)
          first = positions[0]
          first_axis = (positions[1] - first).normalize
          second_axis = (positions[2] - positions[1]).normalize
          return [first_axis, second_axis] if first_axis.length > 0 && second_axis.length > 0
        end

        right = view.camera.direction.cross(view.camera.up).normalize
        [right, view.camera.up.normalize]
      end

      def detect_depth(origin, normal)
        configured_depth = NganKeo.drawer_settings[:depth].mm
        return configured_depth unless normal

        candidates = []
        [normal, normal.reverse].each do |direction|
          start = origin + direction * 2.mm
          hit = Sketchup.active_model.raytest([start, direction])
          next unless hit

          distance = start.distance(hit[0])
          candidates << distance if distance > 10.mm
        end
        candidates.min || configured_depth
      end

      def rectangular_face(face)
        return nil unless face && face.vertices.length >= 3

        face
      end

      def face_under_cursor(view, x, y)
        hit = Sketchup.active_model.raytest(view.pickray(x, y))
        return [nil, nil] unless hit

        path = hit[1] || []
        face = path.reverse.find { |entity| entity.is_a?(Sketchup::Face) }
        [face, hit[0]]
      end

      def opening_from_face(face)
        face = rectangular_face(face)
        return nil unless face

        positions = face.vertices.map(&:position)
        first = positions[0]
        first_edge = positions[1] - first
        second_edge = positions[2] - positions[1]
        return nil if first_edge.length < 1.mm || second_edge.length < 1.mm

        [first, first + first_edge, first + second_edge]
      end

      def face_dimensions(face)
        positions = face.vertices.map(&:position)
        [positions[0].distance(positions[1]), positions[1].distance(positions[2])]
      end

      def add_prism(entities, origin, axis_a, axis_b, extrusion)
        face = entities.add_face(origin, origin + axis_a, origin + axis_a + axis_b, origin + axis_b)
        face.reverse! if face.normal.dot(extrusion) < 0
        face.pushpull(extrusion.length * (face.normal.dot(extrusion).negative? ? -1 : 1))
      end
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions')
      menu.add_item(command)
      menu.add_item(create_command)
      menu.add_item(board_command)
      menu.add_separator
      menu.add_item(update_command)

      toolbar = UI::Toolbar.new('TT - ngan keo')
      toolbar.add_item(command)
      toolbar.add_item(create_command)
      toolbar.add_item(board_command)
      toolbar.add_item(update_command)
      toolbar.show
      schedule_update_check
      file_loaded(__FILE__)
    end
  end
end