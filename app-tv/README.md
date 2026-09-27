# 📺 VolPi Media - Android TV, iPhone & iPad Client App

Ứng dụng xem trực tiếp bóng đá, Anime Yumei và kho phim riêng tư đa nền tảng, thiết kế chuyên biệt cho **Android TV (điều khiển 100% bằng remote)** và **iPhone/iPad (cảm ứng, PiP, thích ứng màn hình)**.

---

## 🌟 Tính Năng Nổi Bật

### 1. ⚽ Trực Tiếp Bóng Đá Xôi Lạc (Real-time Auto-Refresh)
- **Tự động làm mới:** Mỗi khi người dùng bấm vào tab Bóng Đá hoặc mở app, ứng dụng tự động gọi API lấy lịch thi đấu và luồng phát mới nhất từ web Xôi Lạc.
- **Nút [🔄 Làm Mới] cho Remote TV:** Đặt ngay trên thanh tiêu đề để bấm 1 chạm bằng remote.
- **Phân loại ưu tiên:** Trận MU (#1), Trận tâm điểm (#2), Các trận theo giờ (#3).
- **Chọn kênh BLV:** Trích xuất tên BLV thực tế (*BLV TOM, BLV BRADY, BLV FILIP, Full HD...*).

### 2. 🌟 Yumei Anime & Tokusatsu
- 4 Thế giới kinh điển: Pokemon, Super Sentai, Kamen Rider, Power Rangers.
- Danh sách tập phim dạng lưới số, điều khiển remote chuyển tập nhanh chóng.

### 3. 👤 Nút Profile & Kho Phim Riêng Tư (Passcode: 3105)
- **Ngụy trang hoàn hảo:** Nút mang tên `Profile` ở góc trên màn hình, không ai nghi ngờ.
- **Bàn phím TV D-pad:** Bấm phím số ảo trên màn hình hoặc phím số remote.
- **Mã truy cập:** **`3105`**.
- **Cơ chế Xóa dấu vết (Zero-Trace):**
  - Bấm phím **Back** hoặc đổi tab $\rightarrow$ Thoát kho phim, tự động khóa lại ngay lập tức và xóa sạch bộ nhớ tạm.
  - Không bao giờ lưu lịch sử xem phim này ngoài màn hình chính.

### 4. 🎬 Trình Phát Video Siêu Nhẹ (< 50MB RAM)
- Giải mã phần cứng (MediaCodec / AVPlayer), mức tải CPU trên TV chỉ từ **5% - 8%**.
- Tự động giữ màn hình luôn sáng (**Wakelock**).
- **Phím Remote TV:**
  - `OK` / `Enter`: Play / Pause / Hiện điều khiển.
  - `Trái` / `Phải`: Tua nhanh / Tua lùi 10 giây.
  - `Lên` / `Xuống`: Mở thanh chọn kênh BLV hoặc tập phim trực tiếp khi đang xem.
  - Tự ẩn thanh điều khiển sau 3.5 giây.

---

## 🚀 Cách Cài Đặt Lên Android TV

### Cách 1: Tải trực tiếp file APK từ GitHub Actions (Khuyên dùng)
1. Đẩy code lên GitHub repository của bạn.
2. Tab **Actions** trên GitHub sẽ tự động biên dịch và tạo sẵn file **`VolPi-Media-AndroidTV.apk`**.
3. Tải file `.apk` về:
   - Dùng app **Downloader** trên TV: Nhập link tải file `.apk`.
   - Hoặc chép file `.apk` vào USB rồi cắm vào TV cài đặt.
   - Hoặc cài app **Send Files to TV** trên điện thoại và TV để bắn file `.apk` qua mạng WiFi nội bộ.

### Cách 2: Biên dịch thủ công (Nếu máy tính có cài Flutter)
```bash
cd app-tv
flutter pub get
flutter build apk --release
```
File APK xuất xưởng tại: `build/app/outputs/flutter-apk/app-release.apk`.
