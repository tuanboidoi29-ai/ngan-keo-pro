# frozen_string_literal: true

require 'sketchup.rb'
require 'json'

module TT
  module NganKeo
    VERSION = '1.0.0'
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

    def check_for_updates
      unless defined?(Sketchup::Http::Request)
        open_release_page
        return
      end

      request = Sketchup::Http::Request.new(UPDATE_MANIFEST_URL)
      request.start do |_http_request, response|
        if response.status_code.to_i != 200
          open_release_page('Không thể kiểm tra máy chủ cập nhật.')
          next
        end

        manifest = JSON.parse(response.body)
        latest = manifest['version'].to_s
        if newer_version?(latest, VERSION)
          message = "Có bản mới v#{latest} (hiện tại v#{VERSION}).\n\nMở link tải RBZ để cập nhật?"
          UI.messagebox(message) == IDYES && UI.openURL(manifest['rbz_url'].to_s)
        else
          UI.messagebox("TT - ngan keo đang ở phiên bản mới nhất v#{VERSION}.")
        end
      rescue JSON::ParserError
        open_release_page('Manifest cập nhật không hợp lệ.')
      end
    rescue StandardError => error
      open_release_page("Không thể kiểm tra cập nhật: #{error.message}")
    end

    def newer_version?(remote, current)
      remote.split('.').map(&:to_i) > current.split('.').map(&:to_i)
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
        view.invalidate
        update_status
      end

      def onMouseMove(_flags, x, y, view)
        input = view.inputpoint(x, y)
        if input.valid?
          @preview = input.position
          @detected_face = rectangular_face(input.face)
        else
          @detected_face = nil
        end
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
        return unless input.valid?

        if @points.empty?
          @normal = input.face ? input.face.normal : view.camera.direction.reverse
          if (opening = opening_from_face(input.face))
            @points = opening
            update_status
            view.invalidate
            return
          end
        end
        @points << input.position
        if @points.length == 4
          create_drawer
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
        preview_points = @points + [@preview]
        view.draw(GL_LINE_STRIP, preview_points)
      end

      private

      def tooltip_text(input)
        return 'Chọn điểm trên mặt phẳng' unless input.valid?

        if @points.empty? && @detected_face
          width, height = face_dimensions(@detected_face)
          return "Lòng tủ: Rộng #{format_length(width)} x Cao #{format_length(height)} | Click để nhận biết"
        end

        case @points.length
        when 0 then 'Góc 1: bắt đầu vùng ngăn kéo'
        when 1 then "Góc 2: chiều ngang #{distance(@points[0], input.position)}"
        when 2 then "Góc 3: chiều cao #{distance(@points[0], input.position)}"
        else "Kéo sâu: #{depth_for(input.position)}"
        end
      end

      def update_status
        messages = [
          'Chọn góc 1 của vùng tạo ngăn kéo',
          'Chọn góc 2 để xác định chiều ngang',
          'Chọn góc 3 để xác định chiều cao',
          'Chọn điểm thứ 4 để xác định chiều sâu'
        ]
        Sketchup.set_status_text(messages[@points.length], SB_PROMPT)
      end

      def distance(first, second)
        format_length(first.distance(second))
      end

      def format_length(length)
        "#{length.to_mm.round(1)} mm"
      end

      def depth_for(point)
        value = (@normal ? (point - @points.first).dot(@normal).abs : 0)
        (value > 1.mm ? value : DEFAULT_DEPTH).to_l.round(1).to_s + ' mm'
      end

      def create_drawer
        origin, width_end, height_end, depth_point = @points
        width_vector = width_end - origin
        height_vector = height_end - origin
        configured = NganKeo.drawer_settings
        thickness = configured[:thickness].mm
        bottom_thickness = configured[:bottom_thickness].mm
        depth_value = (depth_point - origin).dot(@normal).abs
        depth_value = configured[:depth].mm if depth_value < 1.mm
        depth_vector = @normal.clone
        depth_vector.length = depth_value
        depth_vector.reverse! if (depth_point - origin).dot(@normal).negative?

        width = width_vector.length
        height = height_vector.length
        if width <= thickness * 2 || height <= thickness * 2
          UI.messagebox('Khoảng tạo quá nhỏ cho 4 thanh và tấm đáy.')
          return
        end

        u = width_vector.normalize
        v = height_vector.normalize
        group = Sketchup.active_model.active_entities.add_group
        entities = group.entities
        add_prism(entities, origin, u * thickness, v * height, depth_vector)
        add_prism(entities, origin + u * (width - thickness), u * thickness, v * height, depth_vector)
        add_prism(entities, origin, u * (width - thickness), v * thickness, depth_vector)
        add_prism(entities, origin + v * (height - thickness), u * (width - thickness), v * thickness, depth_vector)

        inner_origin = origin + u * thickness + v * thickness
        add_prism(entities, inner_origin, u * (width - thickness * 2), depth_vector, v * bottom_thickness)
        add_prism(entities, origin, u * width, v * height, depth_vector.reverse * thickness)
        group.name = 'TT - ngan keo'
        Sketchup.active_model.selection.clear
        Sketchup.active_model.selection.add(group)
      end

      def rectangular_face(face)
        return nil unless face && face.vertices.length == 4 && face.edges.length == 4

        face
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
      menu.add_separator
      menu.add_item(update_command)

      toolbar = UI::Toolbar.new('TT - ngan keo')
      toolbar.add_item(command)
      toolbar.add_item(create_command)
      toolbar.add_item(update_command)
      toolbar.show
      file_loaded(__FILE__)
    end
  end
end