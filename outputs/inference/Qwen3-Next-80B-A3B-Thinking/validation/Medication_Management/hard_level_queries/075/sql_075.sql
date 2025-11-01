WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag 
    ON d.icd_code = d_diag.icd_code AND d.icd_version = d_diag.icd_version
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 58 AND 68
    AND d.icd_code = 'J44.0'
    AND d.icd_version = 10
),
med_complexity AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT p.drug) AS complexity_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
    AND p.starttime >= c.admittime
    AND p.starttime <= c.admittime + INTERVAL 72 HOUR
  GROUP BY c.hadm_id
),
readmissions AS (
  SELECT
    a.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = a.subject_id
        AND a2.admittime > a.dischtime
        AND a2.admittime <= a.dischtime + INTERVAL 30 DAY
    ) THEN 1 ELSE 0 END AS readmitted_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
complexity_tertiles AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    mc.complexity_score,
    NTILE(3) OVER (ORDER BY mc.complexity_score) AS tertile,
    r.readmitted_30d
  FROM cohort c
  LEFT JOIN med_complexity mc ON c.hadm_id = mc.hadm_id
  LEFT JOIN readmissions r ON c.hadm_id = r.hadm_id
)
SELECT
  tertile,
  COUNT(*) AS n,
  MIN(complexity_score) AS min_complexity,
  MAX(complexity_score) AS max_complexity,
  AVG(complexity_score) AS mean_complexity,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS mean_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct,
  AVG(CAST(readmitted_30d AS FLOAT64)) * 100 AS readmission_30d_pct
FROM complexity_tertiles
GROUP BY tertile
ORDER BY tertile;