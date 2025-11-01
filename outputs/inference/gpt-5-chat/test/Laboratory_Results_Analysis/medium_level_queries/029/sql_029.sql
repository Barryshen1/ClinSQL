WITH troponin_first AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    ARRAY_AGG(le.valuenum ORDER BY le.charttime ASC LIMIT 1)[OFFSET(0)] AS first_trop_value,
    MIN(le.charttime) AS first_trop_time
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) = 'troponin t'
    AND le.valuenum IS NOT NULL
  GROUP BY le.subject_id, le.hadm_id
),
dx_filtered AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%chest pain%'
     OR LOWER(dd.long_title) LIKE '%myocardial infarction%'
),
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    tf.first_trop_value,
    a.hospital_expire_flag
  FROM dx_filtered dx
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON dx.subject_id = a.subject_id
    AND dx.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN troponin_first tf
    ON a.subject_id = tf.subject_id
    AND a.hadm_id = tf.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND tf.first_trop_value > 0.04
)
SELECT
  COUNT(*) AS num_admissions,
  COUNT(DISTINCT subject_id) AS num_unique_patients,
  MIN(anchor_age) AS min_age,
  MAX(anchor_age) AS max_age,
  AVG(anchor_age) AS avg_age,
  AVG(first_trop_value) AS avg_first_troponin,
  APPROX_QUANTILES(first_trop_value, 2)[OFFSET(1)] AS median_first_troponin,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS num_deaths,
  SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_rate
FROM cohort;