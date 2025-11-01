WITH acs_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id AND a.subject_id = diag.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 73 AND 83
    AND diag.seq_num = 1
    AND diag.icd_version = 10
    AND diag.icd_code IN ('I20.0','I21.0','I21.1','I21.2','I21.3','I21.4')
),
troponin_first AS (
  SELECT 
    hadm_id,
    valuenum,
    ref_range_upper
  FROM (
    SELECT 
      le.hadm_id,
      le.valuenum,
      le.ref_range_upper,
      ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
      ON le.itemid = dli.itemid
    INNER JOIN acs_admissions a
      ON le.hadm_id = a.hadm_id
    WHERE 
      LOWER(dli.label) LIKE '%troponin t%'
      AND le.valuenum IS NOT NULL
      AND le.ref_range_upper IS NOT NULL
  ) ranked
  WHERE rn = 1
),
cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM acs_admissions a
  INNER JOIN troponin_first t
    ON a.hadm_id = t.hadm_id
  WHERE 
    t.valuenum > t.ref_range_upper
)
SELECT 
  COUNT(*) AS cohort_size,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / (24*3600)) AS avg_los_days,
  SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate
FROM cohort;