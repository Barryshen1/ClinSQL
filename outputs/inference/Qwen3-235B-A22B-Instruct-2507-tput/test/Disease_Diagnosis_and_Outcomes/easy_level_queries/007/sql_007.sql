WITH ugi_bleed_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    (icd_version = 9 AND icd_code IN ('5780', '5781', '5789')) OR
    (icd_version = 10 AND icd_code IN ('K920', 'K921', 'K922'))
  )
),
admissions_with_age AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),
ugib_admissions AS (
  SELECT a.*
  FROM admissions_with_age a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN ugi_bleed_codes u
    ON d.icd_code = u.icd_code AND d.icd_version = u.icd_version
  WHERE d.seq_num = 1  -- primary diagnosis
    AND a.gender = 'F'
    AND a.age_at_admission BETWEEN 84 AND 94
)
SELECT
  PERCENTILE_CONT(los_days, 0.75) OVER () - PERCENTILE_CONT(los_days, 0.25) OVER () AS los_iqr
FROM ugib_admissions
LIMIT 1;