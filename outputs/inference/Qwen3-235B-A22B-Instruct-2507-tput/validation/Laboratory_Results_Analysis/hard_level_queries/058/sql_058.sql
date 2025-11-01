WITH patients_age AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
),

-- ACS diagnosis codes (ICD-10)
acs_codes AS (
  SELECT 'I21' AS icd_code UNION ALL
  SELECT 'I20.0' UNION ALL
  SELECT 'I24.0'
),

-- Patients with ACS diagnosis
acs_patients AS (
  SELECT DISTINCT pa.*
  FROM patients_age pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN acs_codes ac
    ON di.icd_code = ac.icd_code AND di.icd_version = 10
  WHERE pa.gender = 'F' AND pa.age_at_admission BETWEEN 40 AND 50
),

-- Lab events in first 48 hours for ACS patients
acs_labs_48h AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN acs_patients a
    ON le.hadm_id = a.hadm_id
  WHERE le.charttime >= a.admittime
    AND le.charttime <= DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL
),

-- Abnormal lab flag: outside reference range
acs_abnormal_labs AS (
  SELECT
    hadm_id,
    CASE
      WHEN ref_range_lower IS NOT NULL AND ref_range_upper IS NOT NULL THEN
        (valuenum < ref_range_lower OR valuenum > ref_range_upper)
      WHEN ref_range_lower IS NOT NULL AND ref_range_upper IS NULL THEN
        valuenum < ref_range_lower
      WHEN ref_range_lower IS NULL AND ref_range_upper IS NOT NULL THEN
        valuenum > ref_range_upper
      ELSE FALSE -- if no reference range, assume normal
    END AS is_abnormal
  FROM acs_labs_48h
),

-- Instability score: count of abnormal labs per admission
acs_instability AS (
  SELECT
    hadm_id,
    SUM(CASE WHEN is_abnormal THEN 1 ELSE 0 END) AS instability_score
  FROM acs_abnormal_labs
  GROUP BY hadm_id
),

-- 90th percentile threshold
threshold AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score
  FROM acs_instability
),

-- High instability ACS patients
high_instability_acs AS (
  SELECT a.*
  FROM acs_patients a
  INNER JOIN acs_instability ai ON a.hadm_id = ai.hadm_id
  CROSS JOIN threshold t
  WHERE ai.instability_score >= t.p90_score
),

-- General inpatients: same age/gender, any diagnosis
general_inpatients AS (
  SELECT pa.*
  FROM patients_age pa
  WHERE pa.gender = 'F'
    AND pa.age_at_admission BETWEEN 40 AND 50
),

-- Labs in first 48h for general inpatients
general_labs_48h AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN general_inpatients g
    ON le.hadm_id = g.hadm_id
  WHERE le.charttime >= g.admittime
    AND le.charttime <= DATETIME_ADD(g.admittime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL
),

general_abnormal_labs AS (
  SELECT
    hadm_id,
    CASE
      WHEN ref_range_lower IS NOT NULL AND ref_range_upper IS NOT NULL THEN
        (valuenum < ref_range_lower OR valuenum > ref_range_upper)
      WHEN ref_range_lower IS NOT NULL AND ref_range_upper IS NULL THEN
        valuenum < ref_range_lower
      WHEN ref_range_lower IS NULL AND ref_range_upper IS NOT NULL THEN
        valuenum > ref_range_upper
      ELSE FALSE
    END AS is_abnormal
  FROM general_labs_48h
),

general_instability AS (
  SELECT
    hadm_id,
    SUM(CASE WHEN is_abnormal THEN 1 ELSE 0 END) AS instability_score
  FROM general_abnormal_labs
  GROUP BY hadm_id
),

-- Final metrics for high-instability ACS group
high_acs_metrics AS (
  SELECT
    'ACS High Instability' AS cohort,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / (24 * 3600)) AS mean_los,
    AVG(CASE WHEN gi.instability_score > 0 THEN 1.0 ELSE 0.0 END) AS critical_lab_rate
  FROM high_instability_acs h
  LEFT JOIN general_instability gi ON h.hadm_id = gi.hadm_id
),

-- Final metrics for general inpatients
general_metrics AS (
  SELECT
    'General Inpatients' AS cohort,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / (24 * 3600)) AS mean_los,
    AVG(CASE WHEN gi.instability_score > 0 THEN 1.0 ELSE 0.0 END) AS critical_lab_rate
  FROM general_inpatients g
  LEFT JOIN general_instability gi ON g.hadm_id = gi.hadm_id
)

-- Combine results
SELECT * FROM high_acs_metrics
UNION ALL
SELECT * FROM general_metrics;