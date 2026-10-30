# 🏦 Loan Portfolio Monitoring & Credit Quality Evaluation — PostgreSQL
### Portofolio Monitoring & Evaluasi Kredit Perbankan | PostgreSQL + pgAdmin

---

## Ringkasan Proyek

Proyek ini mensimulasikan pekerjaan **tim Monitoring & Evaluasi (M&E) kredit** di sebuah bank, mulai dari data mentah hasil ekstraksi sistem hingga laporan kualitas portofolio kredit yang siap dipakai manajemen. Seluruh alur dikerjakan di **PostgreSQL** dengan pola kerja yang lazim di industri perbankan: **staging → cleaning → production → view → analisis → output pelaporan**.

Pertanyaan bisnis yang dijawab:

1. Seberapa sehat kualitas portofolio kredit saat ini (NPL Ratio, kolektibilitas)?
2. Segmen, produk, dan wilayah mana yang menyumbang risiko terbesar?
3. Seberapa efektif penagihan angsuran dari bulan ke bulan (Collection Rate)?
4. Debitur mana yang perlu masuk daftar pantauan (Watch List) dan apa tindak lanjutnya?
5. Berapa cadangan kerugian (PPAP) yang perlu dibentuk?

> Seluruh data pada proyek ini adalah **data simulasi (sintetis)** yang disusun mengikuti struktur dan istilah perbankan nyata. Tidak ada data nasabah sebenarnya.

---

## Dataset

Tiga tabel yang saling berelasi, mencerminkan struktur database *Core Banking System*:

```
debitur (300 baris)
    │  cif  (1 debitur → banyak fasilitas)
    ▼
fasilitas_kredit (400 baris)
    │  id_fasilitas  (1 fasilitas → banyak pembayaran)
    ▼
pembayaran (12.957 baris)
```

| Tabel | Isi | Kolom Kunci |
|---|---|---|
| `debitur` | Profil nasabah peminjam (segmen, pekerjaan, kota, penghasilan) | `cif` |
| `fasilitas_kredit` | Produk pinjaman, plafon, outstanding, kolektibilitas, agunan | `id_fasilitas`, `cif` |
| `pembayaran` | Riwayat angsuran bulanan (jatuh tempo, realisasi, status, denda) | `id_pembayaran`, `id_fasilitas` |

**Cakupan:** segmen Mikro, Kecil, Menengah, dan Konsumer. Produk meliputi KUR, Kredit Modal Kerja, Kredit Investasi, KPR, KKB, Multiguna, dan KTA, dengan wilayah di 10 kota Jawa Timur.

### Masalah Data yang Sengaja Disisipkan

Agar proses cleaning bermakna, data mentah memuat masalah yang umum ditemui di data perbankan:

| Tabel | Masalah | Penanganan |
|---|---|---|
| `debitur` | NIK dan NPWP kosong | Diubah menjadi `NULL` (tidak dihapus, karena profil debitur tetap valid) |
| `fasilitas_kredit` | Suku bunga bernilai 0 | Diganti nilai default 9% |
| `fasilitas_kredit` | Outstanding bernilai negatif | Dikoreksi dengan `ABS()` |
| `pembayaran` | Nominal bayar negatif | Dinormalisasi menjadi 0 |
| `pembayaran` | Nominal bayar kosong | Diisi 0 |
| `pembayaran` | Angka berformat desimal (`83409000.0`) pada kolom teks | Konversi dua tahap `::NUMERIC` lalu `::BIGINT` |

---

## Alur Pengerjaan

```
CSV mentah
   ↓
[1] Schema           →  Pemisahan domain data (schema kredit)
   ↓
[2] DDL              →  Tabel staging (TEXT) + tabel production (constraint, PK, FK, index)
   ↓
[3] DML Insert       →  Audit data kotor → cleaning → insert ke production
   ↓
[4] DML Views        →  Lapisan transformasi (view profil, kualitas portofolio, histori bayar)
   ↓
[5] Analisis         →  NPL, kolektibilitas, konsentrasi, tren, watch list, PPAP, ringkasan eksekutif
   ↓
[6] Output Power BI  →  View final siap dikoneksikan ke dashboard
```

---

## Struktur File

| No | File | Fungsi |
|---|---|---|
| 1 | `loan_monitoring_schema.sql` | Membuat schema `kredit` untuk memisahkan domain data |
| 2 | `loan_monitoring_DDL.sql` | Membuat tabel staging, tabel production, constraint, dan index |
| 3 | `loan_monitoring_DML-Insert_Data.sql` | Audit data kotor di staging, cleaning, dan insert ke production |
| 4 | `loan_monitoring_DML-Views_Transformasi.sql` | View profil kredit debitur, kualitas portofolio, dan histori pembayaran |
| 5 | `loan_monitoring_Analisis.sql` | Query analisis M&E: NPL, kolektibilitas, konsentrasi, tren, watch list, PPAP |
| 6 | `loan_monitoring_powerbi.sql` | View final untuk koneksi ke Power BI |

Urutan eksekusi mengikuti nomor file.

---

## Pembahasan Tiap Tahap dan Konteks Perbankan

### 1. Schema: Pemisahan Domain Data

Seluruh objek ditempatkan di schema `kredit`. Bank umumnya memisahkan database per domain bisnis (kredit, dana pihak ketiga, treasury, pelaporan regulasi) agar hak akses dan tata kelola data lebih terkontrol.

### 2. DDL: Staging dan Production

- **Tabel staging** memakai tipe `TEXT` untuk semua kolom, sehingga data kotor tetap bisa masuk tanpa error dan dapat diaudit lebih dulu.
- **Tabel production** memakai tipe data yang tepat, `PRIMARY KEY`, `FOREIGN KEY`, dan `CHECK` (misalnya kolektibilitas hanya 1 sampai 5, jenis kelamin hanya `L`/`P`).
- **Index** dibuat pada kolom yang sering dipakai untuk JOIN dan filter (`cif`, `kolektibilitas_kode`, `id_fasilitas`, `status_pembayaran`, tanggal jatuh tempo).

💡 **Konteks perbankan:** Pemisahan staging dan production adalah praktik standar dalam proses ETL di bank. Data yang melanggar constraint tidak boleh masuk ke tabel produksi, karena integritas data kredit menjadi dasar pelaporan ke regulator.

### 3. DML Insert: Audit dan Cleaning

Sebelum data dipindahkan, dilakukan audit terhadap nilai kosong, nilai tidak wajar, dan distribusi kategori. Setelah itu data dibersihkan dengan `TRIM`, `INITCAP`, `CASE WHEN`, `COALESCE`, dan `ABS`, lalu dimasukkan dengan `ON CONFLICT DO NOTHING` agar proses aman dijalankan ulang (*idempotent*).

💡 **Konteks perbankan:** Setiap keputusan cleaning punya alasan bisnis. NIK dan NPWP kosong tidak membuat baris dihapus karena profil kredit tetap bernilai. Sebaliknya, fasilitas dengan plafon tidak valid ditolak karena tidak mungkin ada di sistem produksi.

### 4. Views: Lapisan Transformasi

| View | Isi |
|---|---|
| `v_profil_kredit_debitur` | Profil debitur, total plafon dan outstanding, kolektibilitas terburuk, serta **DBR** |
| `v_kualitas_portofolio` | Outstanding per segmen/produk/kolektibilitas, **coverage ratio** agunan |
| `v_histori_pembayaran` | Selisih hari bayar, kekurangan bayar, dan running total (*window function*) |

💡 **Konteks perbankan:**
- **DBR (Debt Burden Ratio)** mengukur beban kredit terhadap penghasilan debitur, indikator kemampuan bayar.
- **Coverage ratio** mengukur seberapa besar agunan menutup outstanding, sebagai perlindungan bila debitur gagal bayar.

### 5. Analisis M&E

| Analisis | Teknik SQL | Makna Bisnis |
|---|---|---|
| **NPL Ratio** (keseluruhan dan per segmen) | CTE, `CASE WHEN`, agregasi | Indikator kesehatan kredit paling diawasi regulator; batas acuan 5% |
| **Laporan kolektibilitas** | `GROUP BY`, window function `SUM() OVER()` | Format menyerupai laporan kualitas aktiva produktif |
| **Konsentrasi risiko per kota** | `JOIN`, persentase terhadap total | Mendeteksi ketergantungan portofolio pada satu wilayah |
| **Tren pembayaran bulanan** | `DATE_TRUNC`, agregasi kondisional | **Collection Rate**, tren keterlambatan, dan denda |
| **Watch List debitur** | CTE, skor risiko gabungan, prioritas tindak lanjut | Early Warning System untuk relationship manager dan tim collection |
| **PPAP** | `CASE` per kolektibilitas, net outstanding setelah agunan | Estimasi cadangan kerugian kredit |
| **Ringkasan eksekutif** | Multi-CTE, status terhadap threshold | Satu query yang merangkum kondisi portofolio untuk manajemen |

💡 **Konteks perbankan:**
- **Kolektibilitas** terdiri dari 5 tingkat: Lancar (1), Dalam Perhatian Khusus (2), Kurang Lancar (3), Diragukan (4), Macet (5). Kredit **NPL** adalah kolektibilitas 3 sampai 5.
- **Collection Rate** mengukur efektivitas penagihan: realisasi pembayaran dibanding total tagihan.
- **PPAP** adalah cadangan kerugian yang langsung menekan laba bank. Semakin tinggi NPL, semakin besar cadangan yang harus dibentuk.

> **Catatan:** Persentase PPAP pada proyek ini (1%, 5%, 15%, 50%, 100%) adalah penyederhanaan untuk tujuan simulasi. Praktik bank saat ini umumnya memakai pendekatan cadangan kerugian penurunan nilai (CKPN) berbasis PSAK 71.

### 6. Output untuk Power BI

Tiga view final disiapkan sebagai sumber data dashboard:

| View | Peruntukan |
|---|---|
| `vw_pbi_npl_summary` | Ringkasan NPL, kolektibilitas, segmen, produk, kota, agunan |
| `vw_pbi_pembayaran_trend` | Tren tagihan, realisasi, status, dan denda per bulan |
| `vw_pbi_watchlist` | Daftar debitur berisiko beserta prioritas tindak lanjut |

---

## Contoh Query

**NPL Ratio per segmen dengan status terhadap threshold:**

```sql
SELECT
    segmen_kredit,
    SUM(outstanding) AS total_outstanding,
    SUM(CASE WHEN kolektibilitas_kode >= 3 THEN outstanding ELSE 0 END) AS outstanding_npl,
    ROUND(
        SUM(CASE WHEN kolektibilitas_kode >= 3 THEN outstanding ELSE 0 END) * 100.0
        / NULLIF(SUM(outstanding), 0), 2
    ) AS npl_ratio_pct
FROM kredit.fasilitas_kredit
WHERE status_kredit = 'Aktif'
GROUP BY segmen_kredit
ORDER BY npl_ratio_pct DESC;
```

**Penanganan angka desimal pada kolom teks (kasus nyata saat cleaning):**

```sql
-- Error: invalid input syntax for type bigint: "83409000.0"
-- Solusi: gunakan NUMERIC sebagai jembatan sebelum BIGINT
CASE WHEN TRIM(nominal_bayar) = '' THEN 0
     WHEN ROUND(nominal_bayar::NUMERIC) < 0 THEN 0
     ELSE ROUND(nominal_bayar::NUMERIC)::BIGINT END
```

---

## Keterampilan yang Ditunjukkan

| Area | Detail |
|---|---|
| **Desain database** | Schema, PK/FK, `CHECK` constraint, index |
| **Data engineering dasar** | Pola staging → production, audit data, cleaning, query idempotent |
| **SQL lanjutan** | CTE, window function, agregasi kondisional, `DATE_TRUNC`, view |
| **Troubleshooting** | Penanganan error casting tipe data dari sumber CSV |
| **Domain perbankan** | NPL, kolektibilitas, coverage ratio, DBR, Collection Rate, PPAP, konsentrasi risiko |
| **Orientasi M&E** | Output berupa indikator, threshold, dan rekomendasi tindak lanjut, bukan sekadar angka |

---

## Cara Menjalankan

1. Install **PostgreSQL** dan **pgAdmin**.
2. Buat database baru bernama `loan_monitoring`.
3. Buka **Query Tool**, lalu jalankan file SQL sesuai urutan nomor (1 sampai 6).
4. Pada langkah import CSV ke tabel staging, gunakan fitur **Import/Export Data** di pgAdmin (format CSV, header aktif).
5. Untuk visualisasi, hubungkan Power BI melalui **Get Data → PostgreSQL Database**, lalu pilih ketiga view `vw_pbi_*`.

---

## Tools

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=flat&logo=postgresql&logoColor=white)
![pgAdmin](https://img.shields.io/badge/pgAdmin-336791?style=flat&logo=postgresql&logoColor=white)
![SQL](https://img.shields.io/badge/SQL-003B57?style=flat&logo=databricks&logoColor=white)
![Power BI](https://img.shields.io/badge/Power_BI-F2C811?style=flat&logo=powerbi&logoColor=black)

---

## Seri Portofolio

| Proyek | Tools | Fokus |
|---|---|---|
| Customer Churn Analysis | Excel dan Power BI | Analisis perilaku dan retensi nasabah |
| Digital Banking Transaction Monitoring | Excel dan Power BI | Cleaning data dan monitoring transaksi digital |
| **Loan Portfolio Monitoring** | **PostgreSQL** | **Monitoring kualitas kredit dan evaluasi risiko** |

---

## Tentang Saya

**Muhammad Fauzi Romadhoni**
D4 Teknik Elektro Industri, Politeknik Elektronika Negeri Surabaya
Bersertifikat K3 Umum (BNSP) | Magang di PT PLN UPT Gresik (Perencana dan Evaluator)
Berfokus pada Monitoring & Evaluasi dan Data Analytics di sektor perbankan

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Connect-0A66C2?style=flat&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/mfauziromadhoni/)
[![Email](https://img.shields.io/badge/Email-Contact-EA4335?style=flat&logo=gmail&logoColor=white)](mailto:mfauzir2477@gmail.com)
[![GitHub](https://img.shields.io/badge/GitHub-Portfolio-181717?style=flat&logo=github&logoColor=white)](https://github.com/mfauziromadhoni)

---

*Portofolio ini dibuat sebagai bagian dari seri portofolio data analytics yang ditujukan untuk posisi Monitoring & Evaluasi di sektor perbankan.*
