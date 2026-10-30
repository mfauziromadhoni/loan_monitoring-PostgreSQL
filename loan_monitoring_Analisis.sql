--####### ANALISIS NPL (Non Performing Loan) ######---

--### NPL Ratio Keseluruhan ###--
-- NPL = kredit dengan kolektibilitas 3, 4, 5
-- NPL Ratio = Outstanding NPL / Total Outstanding × 100%
WITH npl_calc AS(
	SELECT
		SUM(outstanding)						AS total_outstanding,
		SUM(CASE
				WHEN kolektibilitas_kode >= 3
				THEN outstanding ELSE 0 END)	AS outstanding_npl,
		COUNT(id_fasilitas)						AS total_rekening,
		SUM(CASE
				WHEN kolektibilitas_kode >= 3
				THEN 1 ELSE 0 END)				AS rekening_npl
		FROM kredit.fasilitas_kredit
		WHERE status_kredit = 'Aktif'
)
SELECT
	total_outstanding,
	outstanding_npl,
	total_rekening,
	rekening_npl,
	ROUND(outstanding_npl * 100.0 / NULLIF(total_outstanding, 0), 2) AS npl_ratio_pct,
	ROUND(rekening_npl * 100.0 / NULLIF(total_rekening, 0), 2) 	  AS npl_rekening_pct
FROM npl_calc;


--### NPL Ratio per Segmen ###--
SELECT
	segmen_kredit,
	COUNT(id_fasilitas)									AS total_rekening,
	SUM(outstanding)									AS total_outstanding,
	SUM(CASE WHEN kolektibilitas_kode >= 3
			THEN outstanding ELSE 0 END)				AS outstanding_npl,
	ROUND(
		SUM(CASE WHEN kolektibilitas_kode >= 3
				THEN outstanding ELSE 0 END) * 100.0 /
		NULLIF(SUM(outstanding), 0),
		2												
	)													AS npl_ratio_pct,
	--Bandingkan dengan threshold OJK 5%
	CASE 
		WHEN ROUND(
		SUM(CASE WHEN kolektibilitas_kode >= 3
				THEN outstanding ELSE 0 END) * 100.0 /
		NULLIF(SUM(outstanding), 0),
		2) > 5 
		THEN 'Di atas Threshold OJK'
		WHEN ROUND(
		SUM(CASE WHEN kolektibilitas_kode >= 3
				THEN outstanding ELSE 0 END) * 100.0 /
		NULLIF(SUM(outstanding), 0),
		2) > 3
		THEN 'Perlu Perhatian'
		ELSE 'Sehat'
	END													AS status_npl
FROM kredit.fasilitas_kredit
WHERE status_kredit = 'Aktif'
GROUP BY segmen_kredit
ORDER BY npl_ratio_pct DESC;



--### Laporan Kolektibilitas ###--
SELECT
	kolektibilitas_kode								AS kode,
	kolektibilitas_label							AS kualitas_kredit,
	COUNT(id_fasilitas)								AS jumlah_rekening,
	ROUND(COUNT(id_fasilitas) * 100.0 /
		   SUM(COUNT(id_fasilitas)) OVER (), 2) 	AS pct_rekening,
	SUM(outstanding)								AS outstanding,
	ROUND(SUM(outstanding) * 100.0 /
		  SUM(SUM(outstanding)) OVER(), 2)			AS pct_outstanding,
	SUM(nilai_agunan)								AS nilai_agunan,
	ROUND(SUM(nilai_agunan)::NUMERIC /
		  NULLIF(SUM(outstanding), 0) * 100, 2)	AS coverage_ratio_pct,
	ROUND(AVG(hari_tunggakan), 1)					AS avg_hari_tunggakan
FROM kredit.fasilitas_kredit
WHERE status_kredit = 'Aktif'
GROUP BY kolektibilitas_kode, kolektibilitas_label
ORDER BY kolektibilitas_kode;
		

--### Konsentrasi Kredit per Kota ###--
-- Risiko konsentrasi: terlalu banyak kredit di satu area geografis
SELECT
	d.kota,
	COUNT(f.id_fasilitas)							AS jumlah_rekening,
	SUM(f.outstanding)								AS total_outstanding,
	ROUND(SUM(outstanding) * 100.0 /
		  SUM(SUM(outstanding)) OVER (), 2)		AS pct_dari_total,
	SUM(CASE WHEN f.kolektibilitas_kode >= 3
		THEN f.outstanding ELSE 0 END)				AS outstanding_npl,
	ROUND(
		SUM(CASE WHEN f.kolektibilitas_kode >= 3
			THEN f.outstanding ELSE 0 END) * 100.0 /
		NULLIF(SUM(f.outstanding), 0),
		2												
	)													AS npl_ratio_pct
FROM kredit.fasilitas_kredit f
JOIN kredit.debitur d
	ON f.cif = d.cif
WHERE f.status_kredit = 'Aktif'
GROUP BY d.kota
ORDER BY total_outstanding DESC;


--### Tren Pembayaran Bulanan ###--
SELECT
	DATE_TRUNC('month', p.tanggal_jatuh_tempo_angsuran) AS bulan,
	TO_CHAR(DATE_TRUNC('month', p.tanggal_jatuh_tempo_angsuran),
		'Month YYYY')									 AS label_bulan,
	COUNT(p.id_pembayaran)								AS total_angsuran_jatuh_tempo,
	SUM(p.total_angsuran)								AS total_tagihan,
	SUM(p.nominal_bayar)								AS total_terealisasi,
	-- Collection Rate: seberapa banyak tagihan yang berhasil ditagih
	ROUND(SUM(p.nominal_bayar) *100.0 /
		  NULLIF(SUM(p.total_angsuran), 0), 2)			AS collection_rate_pct,
	--Jumlah per Status
	SUM(CASE WHEN p.status_pembayaran = 'Tepat Waktu'
			 THEN 1 ELSE 0 END)							AS tepat_waktu,
	SUM(CASE WHEN p.status_pembayaran = 'Terlambat'
			 THEN 1 ELSE 0 END)							AS terlambat,
	SUM(CASE WHEN p.status_pembayaran = 'Tidak Bayar'
			 THEN 1 ELSE 0 END)							AS tidak_bayar,
	--Total denda terkumpul
	SUM(p.denda)										AS total_denda
FROM kredit.pembayaran p
GROUP BY DATE_TRUNC('month', p.tanggal_jatuh_tempo_angsuran)
ORDER BY bulan;


--### Debitur Watch List ###--
-- Debitur yang perlu dipantau intensif oleh relationship manager
WITH payment_behavior AS(
	SELECT
		p.id_fasilitas,
		COUNT(*)											AS total_angsuran,
		SUM(CASE WHEN p.status_pembayaran = 'Tidak Aktif'
			THEN 1 ELSE 0 END)								AS jumlah_tidak_bayar,
		SUM(CASE WHEN p.status_pembayaran = 'Terlambat'
			THEN 1 ELSE 0 END)								AS jumlah_terlambat,
		ROUND(
			SUM(CASE WHEN p.status_pembayaran = 'Tidak Aktif'
			THEN 1 ELSE 0 END) * 100.0 /
			NULLIF(COUNT(*), 0),
			2
		)													AS pct_tidak_bayar
	FROM kredit.pembayaran p
	GROUP BY p.id_fasilitas
)
SELECT
	d.cif,
	d.nama_debitur,
	d.kota,
	d.pekerjaan,
	d.penghasilan_bulanan,
	f.id_fasilitas,
	f.produk_kredit,
	f.plafon,
	f.outstanding,
	f.kolektibilitas_kode,
	f.kolektibilitas_label,
	f.hari_tunggakan,
	pb.jumlah_tidak_bayar,
	pb.jumlah_terlambat,
	pb.pct_tidak_bayar,
	--skor risiko gabungan
	(f.kolektibilitas_kode * 3
	+ LEAST(pb.jumlah_tidak_bayar, 10)
	+ CASE WHEN f.hari_tunggakan > 90 THEN 5 ELSE 0 END)	AS risk_score,
	--prioritas tindak lanjut
	CASE
		WHEN f.kolektibilitas_kode >= 4 THEN 'SEGERA - Ekskalasi ke Komite Kredit'
		WHEN f.kolektibilitas_kode = 3 THEN 'Tinggi - Kunjungan ke lapangan'
		WHEN f.kolektibilitas_kode = 2 
			AND pb.pct_tidak_bayar > 20 THEN 'SEDANG - Telepon dan Surat Peringatan'
		ELSE 								  'PANTAU - Monitoring rutin'
	END														AS prioritas_tindak_lanjut
FROM kredit.fasilitas_kredit f
JOIN kredit.debitur d ON f.cif = d.cif
JOIN payment_behavior pb ON f.id_fasilitas = pb.id_fasilitas
WHERE f.status_kredit = 'Aktif'
	AND (f.kolektibilitas_kode >= 2 OR pb.pct_tidak_bayar > 15)
ORDER BY risk_score DESC, f.outstanding DESC
limit 50;


--### Perhitungan PPAP ###--
-- PPAP = cadangan kerugian yang wajib dibentuk bank
-- Persentase mengacu POJK No. 40/2019
SELECT
	f.kolektibilitas_kode,
	f.kolektibilitas_label,
	SUM(f.outstanding)										AS total_outstanding,
	SUM(f.nilai_agunan)										AS total_agunan,
	-- Outstanding setelah dikurangi agunan (dasar perhitungan PPAP)
	GREATEST(0, SUM(f.outstanding) - SUM(f.nilai_agunan))	AS net_outstanding,
	-- Persentase PPAP per kolektibilitas (ketentuan OJK)
	CASE f.kolektibilitas_kode
		WHEN 1 THEN 1.0
		WHEN 2 THEN 5.0
		WHEN 3 THEN 15.0
		WHEN 4 THEN 50.0
		WHEN 5 THEN 100.0
	END														AS pct_ppap,
	--Jumlah PPAP yang harus dibentuk
	ROUND(
		GREATEST(0, SUM(f.outstanding) - SUM(f.nilai_agunan))
		* CASE f.kolektibilitas_kode
			WHEN 1 THEN 0.01
			WHEN 2 THEN 0.05
			WHEN 3 THEN 0.15
			WHEN 4 THEN 0.50
			WHEN 5 THEN 1.00
		END,
		0
	)														AS ppap_wajib
FROM kredit.fasilitas_kredit f
WHERE f.status_kredit = 'Aktif'
GROUP BY f.kolektibilitas_kode, f.kolektibilitas_label
ORDER BY f.kolektibilitas_kode;


--### Ringkasan Eksekutif Portofolio Kredit ###--
-- Query tunggal yang merangkum kondisi portofolio untuk laporan manajemen
WITH summary AS(
	SELECT
		COUNT(DISTINCT d.cif)								AS total_debitur,
		COUNT(f.id_fasilitas)								AS total_fasilitas,
		SUM(f.plafon)										AS total_plafon,
		SUM(f.outstanding)									AS total_outstanding,
		--Performing Loan (kolektibilitas 1 - 2)
		SUM(CASE WHEN f.kolektibilitas_kode <= 2
				THEN f.outstanding ELSE 0 END)				AS performing_loan,
		--non performing loan (kolektibilitas 3 - 5)
		SUM(CASE WHEN f.kolektibilitas_kode >= 3
				THEN f.outstanding ELSE 0 END)				AS non_performing_loan,
		SUM(f.nilai_agunan)									AS total_agunan
	FROM kredit.fasilitas_kredit f
	JOIN kredit.debitur d ON f.cif = d.cif
	WHERE f.status_kredit = 'Aktif'
),
payment_summary AS (
	SELECT
		COUNT(*)				AS total_angsuran,
		SUM(total_angsuran)		AS total_tagihan,
		SUM(nominal_bayar)		AS total_terealisasi,
		SUM(denda)				AS total_denda_terkumpul
	FROM kredit.pembayaran		
)
--Skala portofolio
SELECT
	--skala portofolio
	s.total_debitur,
	s.total_fasilitas,
	s.total_plafon,
	s.total_outstanding,
	--kualitas kredit
	ROUND(
		s.non_performing_loan * 100.0 /
		NULLIF(s.total_outstanding, 0), 2
	)												AS npl_ratio_pct,
	--coverage
	ROUND(
		s.total_agunan * 100.0 /
		NULLIF(s.total_outstanding, 0), 2
	)												AS coverage_ratio_pct,
	--collection ratio pct
	ROUND(
		ps.total_terealisasi * 100.0 /
		NULLIF(ps.total_tagihan, 0), 2
	)												AS collection_rate_pct,
	--pendapatan denda
	ps.total_denda_terkumpul,
	--status vs threshold OJK
	CASE
		WHEN ROUND(
		s.non_performing_loan * 100.0 /
		NULLIF(s.total_outstanding, 0), 2) > 5
		THEN 'NPL Melewati Threshold OJK 5%'
		WHEN ROUND(
		s.non_performing_loan * 100.0 /
		NULLIF(s.total_outstanding, 0), 2) > 3
		THEN 'NPL Mendekati Threshold - Waspadai'
		ELSE 'NPL Sehat - Di Bawah Threshold OJK'
	END												AS status_portofolio
FROM summary s, payment_summary ps;
	