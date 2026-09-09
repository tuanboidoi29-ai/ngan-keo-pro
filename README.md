# TT - ngan keo

SketchUp Extension cho phép quản lý ngăn kéo bằng `UI::HtmlDialog`.

## Tính năng

- Tên extension: `TT - ngan keo`
- Version: `1.0.0`
- Creator: `TRẦN TUẤN`
- Menu `Extensions` và toolbar dùng chung `UI::Command`.
- Không mở UI khi SketchUp khởi động; UI chỉ mở khi bấm command.
- Có command kiểm tra manifest phiên bản mới và mở RBZ để cập nhật.
- Đóng gói bằng `ruby package.rb` thành `TT-ngan-keo-1.0.0.rbz`.

## Đóng gói

```bash
ruby package.rb
```

Khi phát hành version mới, cập nhật `VERSION` trong `tt_ngan_keo/main.rb`, version trong
`update.json`, sau đó tạo một GitHub Release chứa file RBZ.