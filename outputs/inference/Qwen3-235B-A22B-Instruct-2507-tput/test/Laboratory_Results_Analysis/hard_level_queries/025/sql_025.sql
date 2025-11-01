WITH patients_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 48 AND 58
),

-- Define hemorrhagic stroke ICD codes (ICD-10: I61, I62)
stroke_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I61', 'I62'))
    AND (LOWER(long_title) LIKE '%hemorrhage%'
         OR LOWER(long_title) LIKE '%hemorrhagic stroke%')
),

stroke_patients AS (
  SELECT DISTINCT pa.*
  FROM patients_age pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN stroke_codes sc
    ON di.icd_code = sc.icd_code
),

-- Control cohort: same age/gender, no stroke diagnosis
control_patients AS (
  SELECT pa.*
  FROM patients_age pa
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    INNER JOIN stroke_codes sc ON di.icd_code = sc.icd_code
    WHERE di.hadm_id = pa.hadm_id
  )
),

-- Lab events in first 72 hours with abnormal flags
lab_instability_base AS (
  SELECT
    le.hadm_id,
    di.category,
    COUNT(*) AS critical_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems di
    ON le.itemid = di.itemid
  INNER JOIN patients_age pa
    ON le.hadm_id = pa.hadm_id
  WHERE le.charttime >= pa.admittime
    AND le.charttime <= DATETIME_ADD(pa.admittime, INTERVAL 72 HOUR)
    AND le.flag IS NOT NULL -- assuming non-null flag indicates critical/abnormal
  GROUP BY le.hadm_id, di.category
),

-- Lab instability score = number of distinct categories with critical labs
lab_score AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT category) AS instability_score,
    SUM(critical_lab_count) AS total_critical_labs
  FROM lab_instability_base
  GROUP BY hadm_id
),

-- Stroke patients with lab scores
stroke_with_score AS (
  SELECT
    s.*,
    COALESCE(ls.instability_score, 0) AS instability_score,
    COALESCE(ls.total_critical_labs, 0) AS total_critical_labs
  FROM stroke_patients s
  LEFT JOIN lab_score ls ON s.hadm_id = ls.hadm_id
),

-- Control patients with lab scores
control_with_score AS (
  SELECT
    c.*,
    COALESCE(ls.instability_score, 0) AS instability_score,
    COALESCE(ls.total_critical_labs, 0) AS total_critical_labs
  FROM control_patients c
  LEFT JOIN lab_score ls ON c.hadm_id = ls.hadm_id
),

-- Compute P90 of instability score in stroke group
p90_value AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score
  FROM stroke_with_score
),

-- Final cohorts
stroke_high_risk AS (
  SELECT
    'Stroke ≥P90' AS cohort,
    hospital_expire_flag,
    los,
    total_critical_labs
  FROM stroke_with_score, p90_value
  WHERE instability_score >= p90_value.p90_score
),

control_summary AS (
  SELECT
    'Control' AS cohort,
    hospital_expire_flag,
    los,
    total_critical_labs
  FROM control_with_score
)

-- Combine results
SELECT
  cohort,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(los) AS mean_los,
  AVG(total_critical_labs) AS avg_critical_labs
FROM (
  SELECT cohort, hospital_expire_flag, los, total_critical_labs
  FROM stroke_high_risk
  UNION ALL
  SELECT cohort, hospital_expire_flag, los, total_critical_labs
  FROM control_summary
)
GROUP BY cohort;