# Deployment Guide - Oracle Cloud TURN Server

## 목차
- [Oracle Cloud 계정 설정](#oracle-cloud-계정-설정)
- [VM 인스턴스 생성](#vm-인스턴스-생성)
- [네트워크 설정](#네트워크-설정)
- [Coturn 설치 및 설정](#coturn-설치-및-설정)
- [보안 강화](#보안-강화)
- [모니터링 설정](#모니터링-설정)
- [프로덕션 체크리스트](#프로덕션-체크리스트)

---

## Oracle Cloud 계정 설정

### 1. 계정 생성
1. https://www.oracle.com/cloud/free/ 접속
2. "Start for free" 클릭
3. 이메일, 국가, 전화번호 입력
4. 신용카드 등록 (인증용, 무료 티어는 청구 없음)
5. 계정 활성화 확인 (이메일 검증)

### 2. Free Tier 리소스 확인
**Compute (영구 무료)**
- VM.Standard.E2.1.Micro (AMD): 1 OCPU, 1GB RAM (2개까지)
- VM.Standard.A1.Flex (ARM): 최대 4 OCPU, 24GB RAM (총합)

**네트워크 (영구 무료)**
- 아웃바운드 데이터 전송: 월 10TB
- 퍼블릭 IPv4: 2개

**추천 선택**: **VM.Standard.A1.Flex (4 OCPU, 24GB RAM)**
- ARM 아키텍처로 성능 우수
- Coturn은 ARM 네이티브 지원
- 동시 접속자 100-200명 처리 가능

---

## VM 인스턴스 생성

### 1. Compute Instance 생성

#### Step 1: 콘솔 접속
1. Oracle Cloud 콘솔 로그인
2. 좌측 메뉴 > Compute > Instances
3. "Create Instance" 클릭

#### Step 2: 기본 정보
```
Name: webrtc-turn-server
Compartment: (root) 또는 원하는 compartment
Availability Domain: 임의 선택 (예: AD-1)
```

#### Step 3: Image and Shape
**Image:**
- OS: Canonical Ubuntu
- Version: 22.04 Minimal (권장)

**Shape:**
- Shape Series: Ampere (ARM)
- Shape Name: VM.Standard.A1.Flex
- OCPU: 4
- Memory (GB): 24

> **참고**: A1.Flex 생성이 안 되면 다른 Availability Domain 시도
> "Out of capacity" 에러 시 몇 시간 후 재시도

#### Step 4: Networking
```
Virtual Cloud Network: 새로 생성 또는 기존 VCN 선택
Subnet: Public Subnet 선택
Public IP Address: Assign a public IPv4 address (필수)
```

#### Step 5: SSH Key
**옵션 1: 자동 생성**
- "Generate a key pair for me" 선택
- Private Key 다운로드 (예: ssh-key-2025-01-18.key)
- 로컬에 저장: `~/.ssh/oracle_cloud.pem`
- 권한 설정: `chmod 600 ~/.ssh/oracle_cloud.pem`

**옵션 2: 기존 키 사용**
- "Upload public key files" 선택
- 로컬의 `~/.ssh/id_rsa.pub` 내용 붙여넣기

#### Step 6: Boot Volume
```
Size (GB): 50 (기본값 사용)
```

#### Step 7: 생성 완료
- "Create" 버튼 클릭
- 프로비저닝 대기 (2-3분)
- Status가 "Running"으로 변경되면 완료

### 2. SSH 연결 확인
```bash
# Public IP 주소 확인 (콘솔의 Instance Details에서)
PUBLIC_IP=XXX.XXX.XXX.XXX

# SSH 접속 테스트
ssh -i ~/.ssh/oracle_cloud.pem ubuntu@$PUBLIC_IP

# 성공하면 프롬프트 변경됨
ubuntu@webrtc-turn-server:~$
```

---

## 네트워크 설정

### 1. VCN Security List 설정

#### Step 1: VCN 콘솔 이동
1. Oracle Cloud 콘솔 > Networking > Virtual Cloud Networks
2. 사용 중인 VCN 클릭 (예: vcn-20250118-xxxx)
3. Security Lists 클릭
4. "Default Security List for vcn-xxx" 클릭

#### Step 2: Ingress Rules 추가
"Add Ingress Rules" 버튼 클릭 후 다음 규칙 추가:

**규칙 1: STUN/TURN TCP**
```
Stateless: ❌ (체크 해제)
Source Type: CIDR
Source CIDR: 0.0.0.0/0
IP Protocol: TCP
Source Port Range: All
Destination Port Range: 3478
Description: TURN TCP
```

**규칙 2: STUN/TURN UDP**
```
Stateless: ❌
Source Type: CIDR
Source CIDR: 0.0.0.0/0
IP Protocol: UDP
Source Port Range: All
Destination Port Range: 3478
Description: TURN UDP
```

**규칙 3: 미디어 릴레이 포트 (UDP)**
```
Stateless: ❌
Source Type: CIDR
Source CIDR: 0.0.0.0/0
IP Protocol: UDP
Source Port Range: All
Destination Port Range: 49152-65535
Description: TURN Media Relay
```

> **중요**: 세 개의 규칙을 모두 추가해야 TURN 서버가 정상 작동합니다.

### 2. Linux 방화벽 설정 (iptables)

Oracle Ubuntu는 기본적으로 iptables가 모든 트래픽을 차단하므로, VCN에서 열어도 VM 내부에서 추가 설정 필요.

```bash
# SSH 접속 후 실행

# 현재 규칙 확인
sudo iptables -L -n

# TURN 포트 개방
sudo iptables -I INPUT -p udp --dport 3478 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 3478 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 49152:65535 -j ACCEPT

# 규칙 영구 저장
sudo apt-get install -y iptables-persistent
sudo netfilter-persistent save

# 확인
sudo iptables -L -n | grep 3478
```

**예상 출력:**
```
ACCEPT     tcp  --  0.0.0.0/0   0.0.0.0/0   tcp dpt:3478
ACCEPT     udp  --  0.0.0.0/0   0.0.0.0/0   udp dpt:3478
ACCEPT     udp  --  0.0.0.0/0   0.0.0.0/0   udp dpts:49152:65535
```

---

## Coturn 설치 및 설정

### 1. 자동 설치 스크립트 사용

#### 스크립트 다운로드
```bash
# GitHub 레포지토리 클론
git clone https://github.com/your-repo/webrtc-hybrid-server.git
cd webrtc-hybrid-server/infrastructure/oracle-cloud/coturn

# 스크립트 실행 권한 부여
chmod +x setup.sh

# 설치 실행 (sudo 필요)
sudo ./setup.sh
```

#### setup.sh 내용 (참고용)
```bash
#!/bin/bash
set -e

echo "========================================"
echo "Coturn TURN Server Installation Script"
echo "========================================"

# 1. 시스템 업데이트
echo "[1/6] Updating system packages..."
apt-get update
apt-get upgrade -y

# 2. Coturn 설치
echo "[2/6] Installing Coturn..."
apt-get install -y coturn

# 3. 설정 파일 백업
echo "[3/6] Backing up default config..."
cp /etc/turnserver.conf /etc/turnserver.conf.backup

# 4. 설정 파일 적용
echo "[4/6] Applying Coturn configuration..."
cat > /etc/turnserver.conf << 'EOF'
# Listening IP (VM의 Private IP로 변경 필요)
listening-ip=10.0.0.X

# External IP (VM의 Public IP로 변경 필요)
external-ip=XXX.XXX.XXX.XXX

# TURN 포트
listening-port=3478
min-port=49152
max-port=65535

# Realm (도메인 또는 IP)
realm=your-domain.com

# 인증 방식: Static credentials
user=testuser:testpass

# 로깅
log-file=/var/log/turnserver.log
verbose

# 보안
no-tls
no-dtls

# 성능
relay-threads=4
EOF

# 5. Private IP와 Public IP 자동 감지 및 적용
PRIVATE_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s ifconfig.me)

sed -i "s/listening-ip=.*/listening-ip=$PRIVATE_IP/" /etc/turnserver.conf
sed -i "s/external-ip=.*/external-ip=$PUBLIC_IP/" /etc/turnserver.conf

echo "Private IP: $PRIVATE_IP"
echo "Public IP: $PUBLIC_IP"

# 6. 서비스 시작
echo "[5/6] Starting Coturn service..."
systemctl enable coturn
systemctl start coturn

# 7. 상태 확인
echo "[6/6] Checking service status..."
systemctl status coturn --no-pager

echo "========================================"
echo "Coturn installation completed!"
echo "Test with: turnutils-uclient -v -u testuser -w testpass $PUBLIC_IP"
echo "========================================"
```

### 2. 수동 설치 (참고용)

자동 스크립트를 사용하지 않는 경우:

```bash
# Coturn 패키지 설치
sudo apt-get update
sudo apt-get install -y coturn

# 설정 파일 편집
sudo nano /etc/turnserver.conf

# 아래 내용 입력 후 저장 (Ctrl+X, Y, Enter)
listening-ip=<VM_PRIVATE_IP>
external-ip=<VM_PUBLIC_IP>
listening-port=3478
min-port=49152
max-port=65535
realm=your-domain.com
user=testuser:testpass
log-file=/var/log/turnserver.log
verbose
no-tls
no-dtls

# 서비스 활성화 및 시작
sudo systemctl enable coturn
sudo systemctl start coturn

# 상태 확인
sudo systemctl status coturn
```

### 3. 설정 검증

#### 로그 확인
```bash
# 실시간 로그 모니터링
sudo tail -f /var/log/turnserver.log

# 서비스 재시작 후 로그
sudo systemctl restart coturn
sudo journalctl -u coturn -f
```

**정상 작동 시 로그 예시:**
```
0: : log file opened: /var/log/turnserver.log
0: : Coturn Version Coturn-4.6.2 'Gorgen'
0: : Listener addr: 10.0.0.5:3478
0: : External IP: XXX.XXX.XXX.XXX
0: : Relay addr: 10.0.0.5:49152-65535
```

#### 로컬 테스트
```bash
# VM 내부에서 테스트 (loopback)
turnutils-uclient -v -u testuser -w testpass 127.0.0.1

# 성공 시 출력:
# 0: Total connect time is 0
# 0: start_mclient: msz=2, tot_send_msgs=0, tot_recv_msgs=0
# 0: Total transmit time is 0
# 0: Total lost packets 0 (0.000000%), total send dropped 0 (0.000000%)
```

#### 외부 테스트
로컬 PC에서 Trickle ICE 도구 사용:
1. https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/ 접속
2. "Add Server" 클릭
3. 설정 입력:
   ```
   TURN or TURNS URI: turn:<VM_PUBLIC_IP>:3478
   TURN username: testuser
   TURN password: testpass
   ```
4. "Gather candidates" 클릭
5. **Done** 상태에서 `relay` 타입 candidate가 보이면 성공

**성공 예시:**
```
relay 49152 udp XXX.XXX.XXX.XXX 12345 typ relay raddr ... rport ...
```

---

## 보안 강화

### 1. Dynamic Credentials (프로덕션 필수)

Static credentials는 테스트용으로만 사용. 프로덕션에서는 Dynamic Credentials 사용 권장.

#### Coturn 설정 변경
```bash
sudo nano /etc/turnserver.conf

# Static credentials 주석 처리
# user=testuser:testpass

# Dynamic credentials 활성화
use-auth-secret
static-auth-secret=YOUR_RANDOM_SECRET_KEY_HERE

# Secret 생성 예시
# openssl rand -hex 32
```

#### 클라이언트에서 임시 Credentials 생성
```kotlin
// Android 예시
fun generateTurnCredentials(username: String, secret: String): Pair<String, String> {
    val timestamp = System.currentTimeMillis() / 1000 + 86400 // 24시간 유효
    val turnUsername = "$timestamp:$username"
    
    val hmac = Mac.getInstance("HmacSHA1")
    val secretKey = SecretKeySpec(secret.toByteArray(), "HmacSHA1")
    hmac.init(secretKey)
    val turnPassword = Base64.encodeToString(
        hmac.doFinal(turnUsername.toByteArray()),
        Base64.NO_WRAP
    )
    
    return Pair(turnUsername, turnPassword)
}
```

### 2. TLS/DTLS 활성화

#### Let's Encrypt 인증서 발급
```bash
# Certbot 설치
sudo apt-get install -y certbot

# 인증서 발급 (도메인 필요)
sudo certbot certonly --standalone -d turn.your-domain.com

# 발급된 인증서 경로
# /etc/letsencrypt/live/turn.your-domain.com/fullchain.pem
# /etc/letsencrypt/live/turn.your-domain.com/privkey.pem
```

#### Coturn 설정 업데이트
```bash
sudo nano /etc/turnserver.conf

# TLS 활성화
tls-listening-port=5349
cert=/etc/letsencrypt/live/turn.your-domain.com/fullchain.pem
pkey=/etc/letsencrypt/live/turn.your-domain.com/privkey.pem

# HTTP/HTTPS 비활성화 (필요 시)
# no-tls 주석 처리 또는 삭제
# no-dtls 주석 처리 또는 삭제
```

#### VCN Security List에 5349 포트 추가
```
Protocol: TCP
Destination Port: 5349
Description: TURN TLS
```

### 3. fail2ban 설정 (DDoS 방어)

```bash
# fail2ban 설치
sudo apt-get install -y fail2ban

# Coturn용 jail 설정
sudo nano /etc/fail2ban/jail.d/coturn.conf

# 다음 내용 입력
[coturn]
enabled = true
port = 3478,5349
protocol = udp
filter = coturn
logpath = /var/log/turnserver.log
maxretry = 10
bantime = 3600
findtime = 600

# 필터 생성
sudo nano /etc/fail2ban/filter.d/coturn.conf

# 다음 내용 입력
[Definition]
failregex = ^.*TURN.*allocation failed.*from <HOST>
ignoreregex =

# 서비스 재시작
sudo systemctl restart fail2ban

# 확인
sudo fail2ban-client status coturn
```

### 4. Rate Limiting

```bash
sudo nano /etc/turnserver.conf

# 추가
max-bps=1000000
bps-capacity=0
```

---

## 모니터링 설정

### 1. 기본 모니터링 (systemctl)

```bash
# 서비스 상태
sudo systemctl status coturn

# 로그 실시간 모니터링
sudo journalctl -u coturn -f

# 리소스 사용량
top
htop  # 설치: sudo apt-get install htop
```

### 2. Prometheus + Grafana (고급)

#### Prometheus Exporter 설치
```bash
# coturn-exporter 설치 (Go 필요)
git clone https://github.com/some-exporter/coturn-exporter.git
cd coturn-exporter
go build -o coturn-exporter

# systemd 서비스 등록
sudo nano /etc/systemd/system/coturn-exporter.service

# 다음 내용 입력
[Unit]
Description=Coturn Prometheus Exporter
After=network.target

[Service]
Type=simple
User=ubuntu
ExecStart=/home/ubuntu/coturn-exporter/coturn-exporter --log-file=/var/log/turnserver.log
Restart=always

[Install]
WantedBy=multi-user.target

# 서비스 시작
sudo systemctl enable coturn-exporter
sudo systemctl start coturn-exporter
```

#### Grafana Dashboard
- Grafana Cloud 무료 티어 사용 권장
- 메트릭: 활성 세션 수, 전송 바이트, 에러율

### 3. 알림 설정

간단한 헬스체크 스크립트:
```bash
# /home/ubuntu/check-coturn.sh
#!/bin/bash

if ! systemctl is-active --quiet coturn; then
    echo "Coturn is down!" | mail -s "TURN Server Alert" your-email@example.com
    sudo systemctl restart coturn
fi

# Crontab 등록 (5분마다 체크)
crontab -e

# 추가
*/5 * * * * /home/ubuntu/check-coturn.sh
```

---

## 프로덕션 체크리스트

배포 전 필수 확인사항:

### 인프라
- [ ] Oracle Cloud Free Tier 리소스 확인 (4 OCPU, 24GB RAM)
- [ ] VM 인스턴스 "Running" 상태
- [ ] Public IP 할당 완료
- [ ] VCN Security List에 3478, 49152-65535 개방
- [ ] Linux iptables 방화벽 설정 완료

### Coturn 설정
- [ ] listening-ip = Private IP 설정
- [ ] external-ip = Public IP 설정
- [ ] Dynamic Credentials 활성화 (`use-auth-secret`)
- [ ] TLS/DTLS 인증서 발급 (Let's Encrypt)
- [ ] 로그 파일 경로 설정 (`/var/log/turnserver.log`)
- [ ] systemd 서비스 enable 완료

### 보안
- [ ] Static credentials 제거 (프로덕션)
- [ ] fail2ban 설치 및 설정
- [ ] Rate limiting 설정 (`max-bps`)
- [ ] SSH key-based 인증 (비밀번호 비활성화)
- [ ] Firestore 보안 규칙 검증

### 테스트
- [ ] Trickle ICE 도구로 TURN 연결 확인
- [ ] Android/iOS 앱에서 실제 통화 테스트
- [ ] 동일 WiFi 환경 (P2P)
- [ ] WiFi ↔ LTE 환경 (STUN)
- [ ] LTE ↔ LTE 환경 (TURN)

### 모니터링
- [ ] Coturn 로그 확인 가능
- [ ] systemctl status 정상
- [ ] (선택) Prometheus/Grafana 연동
- [ ] (선택) 알림 스크립트 설정

### 문서화
- [ ] Public IP 주소 기록
- [ ] TURN credentials 저장 (안전한 곳)
- [ ] 비상 연락망 정리
- [ ] 롤백 계획 수립

---

## 트러블슈팅

### 문제 1: "Out of capacity" 에러 (VM 생성 불가)
**원인**: A1.Flex 인스턴스는 인기가 많아 리소스 부족

**해결책**:
1. 다른 Availability Domain 시도
2. 다른 지역(Region) 시도
3. 몇 시간 후 재시도
4. E2.1.Micro 사용 (성능은 낮지만 생성 가능)

### 문제 2: TURN 연결 실패 (Trickle ICE에서 relay candidate 없음)
**원인**: 방화벽 미개방 또는 설정 오류

**체크리스트**:
1. VCN Security List에 3478, 49152-65535 개방 확인
2. Linux iptables 규칙 확인: `sudo iptables -L -n`
3. Coturn 서비스 실행 중: `sudo systemctl status coturn`
4. listening-ip가 Private IP인지 확인
5. external-ip가 Public IP인지 확인

### 문제 3: 비디오/오디오 품질 저하
**원인**: 네트워크 대역폭 부족 또는 서버 과부하

**해결책**:
1. 클라이언트에서 해상도 낮추기 (720p → 480p)
2. Coturn `relay-threads` 증가 (4 → 8)
3. VM Shape 업그레이드 (Free Tier 한도 내)

### 문제 4: 로그 파일 용량 증가
**원인**: verbose 모드 활성화

**해결책**:
```bash
# 로그 레벨 낮추기
sudo nano /etc/turnserver.conf
# verbose 주석 처리 또는 삭제

# 로그 로테이션 설정
sudo nano /etc/logrotate.d/turnserver

# 다음 내용 입력
/var/log/turnserver.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 turnserver turnserver
    postrotate
        systemctl reload coturn > /dev/null
    endscript
}
```

---

## 다음 단계

배포가 완료되었다면:

1. 클라이언트 앱에 TURN 서버 정보 업데이트
2. 실제 사용자 테스트 진행
3. 모니터링 대시보드 확인
4. 사용량에 따라 리소스 조정

---

**궁금하신 점은 GitHub Issues에 남겨주세요!**
