WITH index_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age AS age_at_admission,
    d.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
    ON a.hadm_id = d_icd.hadm_id AND d_icd.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON d_icd.icd_code = d.icd_code AND d_icd.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND a.insurance LIKE 'Medicare%'
    AND a.admission_location LIKE '%SNF%'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age BETWEEN 77 AND 87
    AND d.long_title LIKE '%acute respiratory failure%'
),
readmission_check AS (
  SELECT
    ia.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ia.subject_id
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= ia.dischtime + INTERVAL 30 DAY
    ) THEN 1 ELSE 0 END AS readmitted
  FROM index_admissions ia
),
los_data AS (
  SELECT
    ia.hadm_id,
    DATEDIFF(ia.dischtime, ia.admittime, 'day') AS los,
    rc.readmitted
  FROM index_admissions ia
  JOIN readmission_check rc
    ON ia.hadm_id = rc.hadm_id
)
SELECT
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) FILTER (WHERE readmitted = 1) AS median_los_readmitted,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) FILTER (WHERE readmitted = 0) AS median_los_not_readmitted,
  (SUM(CASE WHEN los > 8 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percent_stays_gt8
FROM los_data;