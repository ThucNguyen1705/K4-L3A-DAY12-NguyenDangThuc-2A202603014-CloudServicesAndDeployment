# Phiếu Phản Ánh — K4 Level 3A, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng placeholder "Câu trả lời của bạn" dưới mỗi câu bằng câu trả lời.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: **Nguyễn Đăng Thực**  Mã học viên: **2A202603014**

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Tình huống: tôi tạo service trên Render từ `render.yaml`. `AGENT_API_KEY` được
khai báo `sync: false` nên Render hỏi giá trị lúc tạo, và giả sử tôi bấm qua mà
quên điền.

- **Không có mặc định (cách tôi làm):** container chết ngay lúc khởi động. Ở
  máy tôi đã thử bỏ biến và nhận được
  `ValidationError: 1 validation error for Settings / agent_api_key / Field required`.
  Trên Render, health check `/health` không bao giờ lên nên deploy bị đánh dấu
  failed, bản cũ vẫn phục vụ. Tôi thấy lỗi đỏ trong log ngay lúc đang nhìn
  dashboard và sửa trong 1 phút.
- **Mặc định `"changeme"`:** app khởi động bình thường, `/health` 200, deploy
  báo "thành công". Nhưng giá trị `"changeme"` nằm trong `config.py` của một
  repo **public**, nên ai đọc code cũng gọi được `/ask` bằng khóa đó và tiêu
  ngân sách của tôi. Tôi chỉ phát hiện khi nhìn hóa đơn hoặc khi cost guard
  chặn 402 với chính user của mình.

Tôi còn chặn thêm một trường hợp gần giống: biến **có** nhưng **rỗng**
(`AGENT_API_KEY=`). Pydantic mặc định chấp nhận chuỗi rỗng, và khi đó một
request gửi `X-API-Key:` rỗng sẽ khớp khóa. Vì vậy tôi đặt
`Field(min_length=1)` trong `Settings`, và trong compose dùng
`${AGENT_API_KEY:?...}` để compose dừng luôn nếu `.env` thiếu biến.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

Dòng log thật khi tôi chạy `uvicorn app.main:app` ở máy và gọi `/ask`:

```json
{"event": "ask_completed", "level": "info", "timestamp": "2026-09-28T13:46:07.801339+00:00", "user_id": "sv01", "tokens_in": 3, "tokens_out": 37, "cost_usd": 2.265e-05}
```

Hai việc làm được với dòng này mà `print("đã trả lời xong")` không làm được:

1. **Lọc và cộng dồn theo trường.** Công cụ log của cloud parse JSON thành cột,
   nên tôi trả lời được *"user nào tiêu nhiều tiền nhất hôm nay?"* bằng một
   truy vấn kiểu `event="ask_completed" | sum(cost_usd) by user_id`. Với chuỗi
   `print` tự do thì phải viết regex cho từng kiểu câu, và chỉ cần đổi câu chữ
   là regex hỏng.
2. **Phát hiện xu hướng và đặt cảnh báo.** Khi gọi 10 lần liên tiếp với cùng
   user `sv-rate`, tôi thấy `tokens_in` tăng dần 1 → 35 → 79 → … → 392, vì mỗi
   lượt gửi kèm toàn bộ lịch sử. Có trường số thì vẽ được biểu đồ
   `tokens_in` theo thời gian, hoặc đặt cảnh báo khi `level="error"` vượt N
   dòng trong 5 phút. Một dòng `print` không có số liệu, cũng không có mức log
   để lọc.

Thêm nữa: mỗi event nằm gọn trên **một dòng**, nên hệ thống gom log theo dòng
không cắt một event thành nhiều mảnh.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | 1190 MB (`1.19GB`) |
| Multi-stage | 184 MB |

Máy tôi không có Docker nên tôi đo trên runner sạch của GitHub Actions (job
`build` trong `.github/workflows/ci.yml`), bằng lệnh `docker images`. Kết quả
annotation của lần chạy
[#36439610242](https://github.com/ThucNguyen1705/K4-L3A-DAY12-NguyenDangThuc-2A202603014-CloudServicesAndDeployment/actions/runs/36439610242):
`day12-agent:single 1.19GB; day12-agent:ci 184MB; python:3.11-slim 125MB`.

Giải thích: bản multi-stage nhỏ hơn khoảng **6,5 lần**, chênh lệch hơn 1GB.

- **Phần lớn nhất là base image.** Bản multi-stage = 125MB base `python:3.11-slim`
  cộng khoảng 59MB thư viện và code. Vậy bản 1 stage có khoảng 1,1GB là base
  `python:3.11` đầy đủ: bộ Debian gần như đầy đủ với `gcc`, `make`, header
  `-dev`, `git`, `curl`, man pages… Đó là đồ nghề để **build**, lúc **chạy** app
  không cần.
- **pip cache:** bản 1 stage chạy `pip install` không có `--no-cache-dir`, nên
  các file wheel đã tải về còn nằm lại trong `/root/.cache/pip` của image.
- **Multi-stage giữ được gọn** vì stage `builder` cài thư viện vào `/install`,
  còn stage `runtime` chỉ `COPY --from=builder /install /usr/local` cùng
  `app/`, `utils/`. Mọi thứ khác của stage builder bị bỏ lại, không vào image
  cuối.

Image nhỏ nghĩa là deploy nhanh hơn: Render phải kéo image mỗi lần deploy. Nó
cũng ít phần mềm hơn, tức ít CVE phải vá hơn.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

Trong CI, tôi build image một lần, thêm một dòng comment vào cuối
`app/main.py`, rồi build lại với `--progress=plain`. Kết quả thật:

```
CACHED [builder 2/4] WORKDIR /build
CACHED [builder 3/4] COPY requirements.txt .
CACHED [builder 4/4] RUN pip install --no-cache-dir --prefix=/install -r requirements.txt
CACHED [runtime 2/6] WORKDIR /app
CACHED [runtime 3/6] COPY --from=builder /install /usr/local
CACHED [runtime 4/6] RUN useradd --create-home --uid 10001 appuser
RUN    [runtime 5/6] COPY app ./app
RUN    [runtime 6/6] COPY utils ./utils
```

(Dòng `FROM python:3.11-slim` cũng hiện là "chạy", nhưng đó chỉ là bước tra
digest của base image, không tải hay build lại gì.)

- **Dùng lại cache:** toàn bộ stage `builder`, gồm cả `pip install` là bước
  chậm nhất, và các bước đầu của `runtime`. Lý do là `requirements.txt` không
  đổi, nên checksum của layer không đổi.
- **Chạy lại:** `COPY app` vì nội dung `app/main.py` đổi, và `COPY utils` vì
  Docker hủy cache **từ layer đầu tiên thay đổi trở xuống**. Cả hai chỉ là copy
  vài KB nên gần như tức thì.

Nếu đặt `COPY . .` **trước** `RUN pip install`, layer `COPY . .` sẽ đổi mỗi khi
sửa bất kỳ file nào. Mọi layer sau nó, gồm `pip install`, mất cache và phải
tải lại toàn bộ fastapi, uvicorn, pydantic, redis… Mỗi lần sửa một dấu phẩy là
mất thêm vài chục giây đến vài phút, và CI hay Render phải làm lại việc đó ở
mỗi lần deploy.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

Chuỗi sự kiện khi container chạy bằng root:

1. Code hoặc một thư viện có lỗ hổng cho phép thực thi lệnh từ xa (RCE), ví
   dụ deserialize dữ liệu không tin cậy hoặc truyền input của user vào
   `subprocess`.
2. Kẻ tấn công chạy lệnh với quyền của process Python, tức là **uid 0 (root)**.
3. Là root trong container, hắn làm được mọi thứ: đọc biến môi trường
   (`AGENT_API_KEY`, `REDIS_URL` kèm mật khẩu), sửa code trong image để cài
   backdoor, `apt install` công cụ tấn công.
4. Không có user namespace thì uid 0 trong container **chính là** uid 0 trên
   host, chỉ bị ngăn bởi namespace và capabilities. Chỉ cần thêm một lỗ hổng
   thoát container (ví dụ CVE-2019-5736 của runc: ghi đè binary `runc` trên
   host, và lỗi này cần quyền root trong container), hoặc một mount nguy hiểm
   như `/var/run/docker.sock`, là hắn thành root trên máy host.

`USER appuser` (uid 10001) cắt chuỗi này **ở bước 2**: RCE chỉ cho quyền của
một user thường. User đó không cài được gói, không ghi được vào
`/usr/local` (thư viện do root sở hữu), và các lỗi thoát container cần root như
ở bước 4 không dùng được. File trên volume mount ra host cũng chỉ được truy cập
với uid 10001, một uid không có quyền gì trên host.

Tôi còn cố ý **không** `--chown` source code cho `appuser`: `/app/app` thuộc
root, `appuser` chỉ đọc được. Nếu bị RCE, kẻ tấn công cũng không sửa được code
để cài backdoor. CI có một bước kiểm tra `touch /app/app/main.py` phải thất bại.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

**Tối đa 20 request trong 2 giây**, gấp đôi hạn mức.

Cách đạt được: bộ đếm theo phút đồng hồ reset về 0 đúng lúc giây 00. Người dùng
gửi 10 request lúc 10:00:59 (đầy quota của phút 10:00), đợi qua mốc 10:01:00,
rồi gửi tiếp 10 request lúc 10:01:01 (quota mới của phút 10:01). Cả 20 đều
"đúng luật". Nếu canh sát mốc (10:00:59.9 và 10:01:00.0) thì 20 request dồn
trong khoảng 0,1 giây.

Với sliding window, lúc nhận request tôi đếm số request trong đúng 60 giây
**tính ngược từ thời điểm hiện tại** (`zremrangebyscore(key, 0, now - 60)` rồi
`zcard`). Ở bất kỳ thời điểm nào, 60 giây gần nhất cũng chỉ chứa tối đa 10
request, nên 2 giây bất kỳ cũng không quá 10. Khi chạy thật ở máy, tôi gửi 15
request liên tiếp trong khoảng 3 giây và nhận
`200 200 200 200 200 200 200 200 200 200 429 429 429 429 429`, kèm header
`Retry-After: 60`.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

| | Rate limit | Cost guard |
|---|---|---|
| Đếm cái gì | **số request** | **số tiền** (USD) |
| Cửa sổ | 60 giây trượt | cả tháng (`cost:<user>:<YYYY-MM>`) |
| Bảo vệ | năng lực phục vụ, chống spam dồn dập | ngân sách, chống tiêu tiền dần dần |
| Mã lỗi | 429 + `Retry-After` | 402 |

**Rate limit cho qua, cost guard phải chặn:** một user gửi đều 5 request/phút
(dưới hạn mức 10), nhưng mỗi request có prompt rất dài, hoặc hội thoại dài vì
lịch sử được gửi kèm. Ở máy tôi đã thấy `tokens_in` của cùng một user tăng từ 1
lên 392 chỉ sau 10 lượt. Với LLM thật và prompt 50k token, chạy liên tục 24/7
vẫn không bao giờ chạm 429, nhưng tổng chi phí vượt 10 USD trong vài giờ.
Cost guard trả 402 từ đó tới hết tháng.

**Cost guard cho qua, rate limit phải chặn:** một script gửi 15 câu `"test"`
trong 3 giây. Tổng chi phí khoảng 0,0008 USD, không đáng kể so với 10 USD,
nhưng 5 request cuối bị 429 (tôi đã quan sát đúng như vậy). Tình huống này
không làm tốn tiền, nhưng nếu không chặn thì một client lỗi vòng lặp có thể
chiếm hết worker và làm service chậm với mọi người khác.

Cả hai đều được kiểm tra **trước** khi gọi LLM, theo thứ tự 401 → 429 → 402,
vì tiền mất ở bước gọi LLM.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

Giả sử orchestrator probe mỗi 10 giây và restart sau 3 lần fail liên tiếp:

1. **t = 0s:** Redis mất kết nối. Cả 3 container vẫn chạy bình thường; những
   request không cần Redis vẫn phục vụ được.
2. **t ≈ 0–10s:** probe gộp gọi Redis ở cả 3 container, cả 3 cùng trả 503. Ba
   container chung một dependency nên chúng hỏng **cùng lúc**, không có
   container nào "khỏe" để gánh.
3. **t ≈ 30s:** đủ 3 lần fail, orchestrator coi cả 3 là "chết" và **restart cả
   3**. Request đang xử lý dở bị cắt, load balancer không còn backend nào,
   client nhận 502. Sự cố của Redis giờ thành sự cố của cả service.
4. **t ≈ 30s+:** Redis có thể vừa quay lại, nhưng container mới còn đang khởi
   động. Nếu Redis về chậm hơn một chút, container mới lại fail probe và bị
   restart tiếp. Orchestrator chuyển sang **back-off** (đợi 10s, 20s, 40s…
   giữa các lần restart), nên thời gian sập **dài hơn** 30 giây Redis mất.

Khi tách hai endpoint như tôi làm:

- `/health` (liveness) không chạm Redis, nên vẫn 200 và **không container nào
  bị restart**.
- `/ready` (readiness) trả 503, load balancer tạm **ngừng gửi** request vào
  (không restart). Khi Redis quay lại, `/ready` lên 200 và traffic vào lại ngay,
  không mất thời gian khởi động.

**Kiểm chứng thật:** job `integration` trong CI dựng 3 agent + Nginx + Redis,
rồi chạy `docker compose stop redis` và gọi qua Nginx. Kết quả annotation:
`/health=200 /ready=503`. Nghĩa là liveness vẫn báo "sống" (không bị restart),
còn readiness báo "đừng gửi traffic". Sau `docker compose start redis`, `/ready`
trở lại 200 mà không container nào phải khởi động lại.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

Máy tôi không có Docker nên tôi làm hai thí nghiệm thật:

**(a) State trong RAM của từng process.** Tôi chạy 3 process uvicorn ở cổng
8001, 8002, 8003, mỗi process dùng `REDIS_URL=fake://` (Redis giả nằm trong RAM
của chính process đó, tương đương một dict Python). Sau đó tôi gửi 6 request
cùng `X-User-Id: sv01`, xoay vòng như load balancer round-robin:

```
request 1 → instance :8001 → history_length = 0
request 2 → instance :8002 → history_length = 0
request 3 → instance :8003 → history_length = 0
request 4 → instance :8001 → history_length = 2
request 5 → instance :8002 → history_length = 2
request 6 → instance :8003 → history_length = 2
```

Con số **nhảy lung tung và thấp hơn thực tế**: mỗi instance chỉ nhớ những lượt
đi qua chính nó. Ở lượt thứ 4, user đã hỏi 3 câu nhưng agent chỉ "nhớ" 1. Nếu
một container restart, phần lịch sử của nó mất hẳn.

**(b) State trong Redis dùng chung.** Cùng user, 5 lượt liên tiếp, kết quả là
`0, 2, 4, 6, 8`: tăng đều 2 mỗi lượt (1 message user + 1 message assistant),
bất kể instance nào xử lý. Lý do là mọi instance cùng đọc/ghi key
`history:sv01` trong Redis.

**(c) `--scale agent=3` thật, qua Nginx.** Trên runner của GitHub Actions
(job `integration`), tôi chạy
`docker compose -f docker-compose.yml -f docker-compose.lb.yml up --scale agent=3`
rồi gửi 6 request cùng `X-User-Id: sv01` vào Nginx ở cổng 8080. Kết quả:

```
history_length = 0 2 4 6 8 10
container xử lý: agent-2 agent-3 agent-1 agent-2 agent-3 agent-1
```

Nginx rải request qua **cả 3 container**, vậy mà `history_length` vẫn tăng đều
0 → 10, vì lịch sử nằm ở Redis chứ không nằm trong RAM container nào. Nếu dùng
dict Python, kết quả sẽ giống thí nghiệm (a): `0 0 0 2 2 2`.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

> *Câu trả lời của bạn*
