# Engram Private Network Helper Scripts

## 0. Giới thiệu sơ bộ về Engram

**Engram** là một mạng blockchain hướng tới kiến trúc tách lớp, trong đó phần đồng thuận, lưu trữ dữ liệu và truy cập dữ liệu có thể được triển khai thành các node chuyên biệt. Trong mô hình này, các node không nhất thiết phải cùng làm toàn bộ công việc của mạng, mà có thể đảm nhiệm từng vai trò riêng như validator, bridge node hoặc light node.

Ở mức tổng quát, Engram có thể được hiểu theo 3 nhóm thành phần chính:

- **Validator/Core node**: tham gia sản xuất block, đồng thuận và cung cấp endpoint core RPC/gRPC cho các node khác.
- **Bridge node**: kết nối với core node, đồng bộ dữ liệu block/header và đóng vai trò trung gian để các light node có thể truy xuất dữ liệu từ mạng.
- **Light node**: node nhẹ, dùng trusted peers để lấy header và kiểm tra dữ liệu mà không cần tự chạy toàn bộ hạ tầng validator/core.

Các script trong repo này giúp khởi chạy nhanh bridge node và light node bằng Docker Compose. Người dùng chỉ cần chỉnh đúng IP, port và peer ID của các trusted peers, sau đó chạy script tương ứng theo hệ điều hành.


Repository này chứa các script hỗ trợ chạy **Engram Bridge Node** và **Engram Light Node** bằng Docker Compose.

## 1. Cấu trúc file

```text
.
├── bridge.sh   # Script Linux/Ubuntu để chạy Engram Bridge Node
├── light.sh    # Script Linux/Ubuntu/WSL để chạy Engram Light Node
└── light.bat   # Script Windows CMD để chạy Engram Light Node
```

## 2. Yêu cầu trước khi chạy

Máy chạy script cần có:

- Docker
- Docker Compose v2, dùng lệnh `docker compose`
- Quyền chạy Docker với user hiện tại
- Kết nối mạng tới các validator/bridge node đã cấu hình trong script

Kiểm tra Docker:

```bash
docker --version
docker compose version
docker info
```

Nếu dùng Ubuntu mà `docker info` báo permission denied, thêm user vào group `docker`:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

## 3. Chạy Bridge Node trên Linux/Ubuntu

Cấp quyền chạy cho script:

```bash
chmod +x bridge.sh
```

Khởi động bridge node:

```bash
./bridge.sh up
```

Xem log:

```bash
./bridge.sh logs
```

Dừng bridge node:

```bash
./bridge.sh down
```

Restart bridge node:

```bash
./bridge.sh restart
```

Xem trạng thái container:

```bash
./bridge.sh ps
```

In file Docker Compose được sinh ra:

```bash
./bridge.sh config
```

Reset bridge node từ đầu:

```bash
./bridge.sh reset
```

> Lưu ý: `reset` thường sẽ xóa dữ liệu node store cũ và init lại node. Chỉ dùng khi bạn chắc chắn muốn chạy lại từ đầu.

## 4. Chạy Light Node trên Linux/Ubuntu/WSL

Cấp quyền chạy:

```bash
chmod +x light.sh
```

Khởi động light node:

```bash
./light.sh up
```

Xem log:

```bash
./light.sh logs
```

Dừng light node:

```bash
./light.sh down
```

Restart light node:

```bash
./light.sh restart
```

Xem trạng thái:

```bash
./light.sh ps
```

In Docker Compose được sinh ra:

```bash
./light.sh config
```

Reset light node từ đầu:

```bash
./light.sh reset
```

## 5. Chạy Light Node trên Windows

Mở **Command Prompt** hoặc **PowerShell** tại thư mục chứa `light.bat`.

Khởi động light node:

```bat
light.bat up
```

Xem log:

```bat
light.bat logs
```

Dừng light node:

```bat
light.bat down
```

Restart:

```bat
light.bat restart
```

Xem trạng thái:

```bat
light.bat ps
```

Reset light node:

```bat
light.bat reset
```

## 6. Các command hỗ trợ

Các script thường hỗ trợ các command sau:

| Command | Ý nghĩa |
|---|---|
| `up` | Sinh `docker-compose.yml`, chuẩn bị thư mục dữ liệu, sau đó chạy container |
| `down` | Dừng và xóa container/network do compose tạo ra |
| `restart` | Dừng rồi chạy lại node |
| `logs` | Xem log realtime |
| `ps` | Xem trạng thái container |
| `pull` | Pull lại Docker image mới nhất theo tag trong script |
| `config` | In nội dung `docker-compose.yml` được sinh ra |
| `reset` | Dừng node, xóa store cũ, tạo lại store và chạy lại từ đầu |

## 7. Kiểm tra node đã chạy hay chưa

Sau khi chạy `up`, kiểm tra container:

```bash
docker ps
```

Xem log:

```bash
./light.sh logs
```

hoặc:

```bash
docker logs -f <container_name>
```

Ví dụ với light node:

```bash
docker logs -f engram-light-node-test
```

Kiểm tra RPC light node trên host:

```bash
curl http://localhost:26762/header/1
```

Nếu chạy trên máy khác, thay `localhost` bằng IP của máy đang chạy light node.

## 8. Cấu hình peer trong Light Node

Light node cần kết nối tới bridge node thông qua các flag như:

```bash
--headers.trusted-peers <MULTIADDR>
--p2p.mutual <MULTIADDR>
```

Ví dụ multiaddr:

```bash
/ip4/103.67.203.71/tcp/2201/p2p/<PEER_ID>
/ip4/131.153.224.169/tcp/2221/p2p/<PEER_ID>
```

Trong đó:

- `/ip4/...` là IP public của bridge node.
- `/tcp/...` là port P2P được expose ra ngoài host.
- `/p2p/...` là peer ID thật của node đang chạy ở IP/port đó.

Nếu gặp lỗi:

```text
peer id mismatch
```

nghĩa là IP/port đã tới được node, nhưng peer ID đang khai báo không khớp với private key thật của node đó. Cần lấy lại peer ID đúng từ log hoặc từ config/store của bridge node.

## 9. Lưu ý về port Docker

Nếu compose bridge có mapping dạng:

```yaml
ports:
  - "2221:2121"
```

thì:

- Container nội bộ Docker network dùng port `2121`.
- Máy bên ngoài Docker network phải dùng port `2221`.

Ví dụ:

```bash
# Container cùng Docker network
/dns4/engram-bridge1/tcp/2121/p2p/<PEER_ID>

# Máy/server khác kết nối qua public IP
/ip4/131.153.224.169/tcp/2221/p2p/<PEER_ID>
```

## 10. Lỗi thường gặp

### 10.1. `keystore: permissions of key 'p2p-key' are too relaxed`

Lỗi ví dụ:

```text
keystore: permissions of key 'p2p-key' are too relaxed: required: 0600, got: 0777
```

Nguyên nhân: file private key bị chmod quá rộng, thường do `chmod -R 777 ./light`.

Cách sửa:

```bash
sudo find ./light -type d -exec chmod 700 {} \;
sudo find ./light -type f -exec chmod 600 {} \;
```

Sau đó chạy lại:

```bash
./light.sh up
```

### 10.2. `TRUSTED_PEERS variable is not set`

Lỗi ví dụ:

```text
The "TRUSTED_PEERS" variable is not set. Defaulting to a blank string.
```

Nguyên nhân: Docker Compose expand biến `$TRUSTED_PEERS` trước khi container chạy.

Cách sửa trong compose: dùng `$$TRUSTED_PEERS` thay vì `$TRUSTED_PEERS`.

Ví dụ:

```bash
--headers.trusted-peers "$$TRUSTED_PEERS"
--p2p.mutual "$$TRUSTED_PEERS"
```

### 10.3. `open /home/engram/.check: permission denied`

Nguyên nhân: container không có quyền ghi vào thư mục mounted volume.

Cách xử lý nhanh:

```bash
sudo chown -R $(id -u):$(id -g) ./light
chmod -R u+rwX ./light
```

Hoặc chạy container với user phù hợp trong compose.

### 10.4. `unknown command "/ip4/..."`

Nguyên nhân: multiaddr bị tách thành argument riêng do lỗi xuống dòng hoặc quote sai trong command.

Cách sửa: gom peer list vào biến và quote lại:

```bash
TRUSTED_PEERS="/ip4/103.67.203.71/tcp/2201/p2p/<PEER_ID_1>,/ip4/131.153.224.169/tcp/2221/p2p/<PEER_ID_2>"

--headers.trusted-peers "$TRUSTED_PEERS"
--p2p.mutual "$TRUSTED_PEERS"
```

Trong Docker Compose heredoc, nếu muốn biến được expand bên trong container, dùng:

```bash
--headers.trusted-peers "$$TRUSTED_PEERS"
```

## 11. Quy trình chạy khuyến nghị

### Bridge node

```bash
chmod +x bridge.sh
./bridge.sh up
./bridge.sh logs
```

### Light node Linux/WSL

```bash
chmod +x light.sh
./light.sh up
./light.sh logs
```

### Light node Windows

```bat
light.bat up
light.bat logs
```

## 12. Dọn sạch và chạy lại từ đầu

Dùng khi store bị lỗi, permission bị hỏng hoặc muốn init lại node:

```bash
./light.sh reset
```

hoặc với bridge:

```bash
./bridge.sh reset
```

Trên Windows:

```bat
light.bat reset
```

## 13. Ghi chú bảo mật

- Không public private key trong thư mục store.
- Không commit thư mục dữ liệu node lên GitHub, ví dụ: `./light`, `./bridge`, `./celes-bridge1`, `./celes-bridge2`.
- Nên thêm vào `.gitignore`:

```gitignore
light/
bridge/
celes-bridge*/
docker-compose.yml
*.log
```
