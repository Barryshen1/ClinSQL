WITH base_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 68 AND 78
    AND a.dischtime IS NOT NULL
),

diagnosis_flags AS (
  SELECT
    b.hadm_id,
    b.admittime,
    b.dischtime
  FROM base_admissions AS b
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = b.subject_id
   AND di.hadm_id = b.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di2
    ON di.icd_code = di2.icd_code
   AND di.icd_version = di2.icd_version
  GROUP BY b.hadm_id, b.admittime, b.dischtime
  HAVING MAX(CASE WHEN LOWER(di2.long_title) LIKE '%pneumonia%' THEN 1 ELSE 0 END) = 1
     AND MAX(CASE WHEN LOWER(di2.long_title) LIKE '%copd%' THEN 1 ELSE 0 END) = 1
),

los_values AS (
  SELECT df.hadm_id,
         TIMESTAMP_DIFF(df.dischtime, df.admittime, SECOND) / 86400 AS los_days
  FROM diagnosis_flags AS df
)

SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(74)] AS los_75th_percentile_days
FROM los_values;