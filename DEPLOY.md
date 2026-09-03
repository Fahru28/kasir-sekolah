# Deploy Kasir Sekolah ke VPS sendiri

## 1. Siapkan VPS (Ubuntu 22.04 / 24.04, 1GB RAM minimal)
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# logout & login lagi
```

## 2. Clone repo
```bash
git clone https://github.com/Fahru28/kasir-sekolah.git
cd kasir-sekolah
```

## 3. Buat .env
```bash
cp .env.example .env
# generate secret:
openssl rand -hex 64
# paste ke SECRET_KEY_BASE di .env, lalu edit kalau perlu
nano .env
```

## 4. Jalankan
```bash
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml logs -f web
# cek: http://IP_VPS:3000
```

## 5. Bikin user admin
```bash
docker compose -f docker-compose.prod.yml exec web bundle exec rails runner "User.create!(email:'admin@sekolah.id', password:'password123', password_confirmation:'password123')"
```

## 6. Domain + HTTPS (pakai Caddy)
Tambah service caddy di docker-compose.prod.yml atau pakai Nginx reverse proxy.
Contoh Caddyfile:
```
kasir.sekolahmu.id {
  reverse_proxy web:3000
}
```

## Update kode (deploy ulang)
```bash
git pull
docker compose -f docker-compose.prod.yml up -d --build
```

