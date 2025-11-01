WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 47 AND 57
),

ihd_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_version = 10
    AND (
      LOWER(d.long_title) LIKE '%ischemic heart disease%'
      OR d.icd_code LIKE 'I20%'
      OR d.icd_code LIKE 'I21%'
      OR d.icd_code LIKE 'I22%'
      OR d.icd_code LIKE 'I23%'
      OR d.icd_code LIKE 'I24%'
      OR d.icd_code LIKE 'I25%'
    )
),

troponin_t_values AS (
  SELECT
    le.hadm_id,
    le.charttime,
    le.valuenum AS troponin_t_value
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) = 'troponin t'
    AND le.valuenum IS NOT NULL
),

first_troponin_t AS (
  SELECT
    hadm_id,
    MIN(charttime) AS first_troponin_time
  FROM troponin_t_values
  GROUP BY hadm_id
),

first_troponin_t_values AS (
  SELECT
    tt.hadm_id,
    tt.troponin_t_value
  FROM troponin_t_values tt
  INNER JOIN first_troponin_t ftt
    ON tt.hadm_id = ftt.hadm_id AND tt.charttime = ftt.first_troponin_time
)

SELECT
  APPROX_QUANTILES(t.troponin_t_value, 1000)[OFFSET(500)] AS median_troponin_t,
  APPROX_QUANTILES(t.troponin_t_value, 1000)[OFFSET(250)] AS q1_troponin_t,
  APPROX_QUANTILES(t.troponin_t_value, 1000)[OFFSET(750)] AS q3_troponin_t
FROM first_troponin_t_values t
INNER JOIN patient_admissions pa
  ON t.hadm_id = pa.hadm_id
INNER JOIN ihd_diagnoses ihd
  ON pa.hadm_id = ihd.hadm_id
WHERE t.troponin_t_value > 0.014;