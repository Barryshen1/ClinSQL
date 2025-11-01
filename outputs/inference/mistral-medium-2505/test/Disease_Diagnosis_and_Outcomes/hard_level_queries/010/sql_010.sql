WITH
-- Define age range and gender filter
male_patients_39_49 AS (
  SELECT
    subject_id,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 39 AND 49
),

-- Get all admissions for these patients
all_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    -- Calculate length of stay in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Check for 30-day mortality
    CASE WHEN a.deathtime IS NOT NULL AND TIMESTAMP_DIFF(a.deathtime, a.dischtime, DAY) <= 30 THEN 1 ELSE 0 END AS mortality_30day
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    male_patients_39_49 p ON a.subject_id = p.subject_id
  WHERE
    a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Identify DKA patients using ICD codes
dka_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    all_admissions a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    -- ICD-9 codes for DKA
    (d.icd_version = 9 AND d.icd_code LIKE '250.1%')
    OR
    -- ICD-10 codes for DKA
    (d.icd_version = 10 AND (
      d.icd_code LIKE 'E10.1%' OR
      d.icd_code LIKE 'E11.1%' OR
      d.icd_code LIKE 'E13.1%'
    ))
),

-- Get SAPS-II scores (risk score) from chartevents
risk_scores AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    MAX(ce.valuenum) AS sapsii_score
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    di.label = 'SAPS-II'
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.subject_id, ce.hadm_id
),

-- Identify cardiovascular complications
cardio_complications AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    all_admissions a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    -- ICD-9 codes for cardiovascular complications
    (d.icd_version = 9 AND (
      d.icd_code LIKE '410.%' OR  -- Acute myocardial infarction
      d.icd_code LIKE '428.%' OR  -- Heart failure
      d.icd_code LIKE '433.%' OR  -- Occlusion and stenosis of cerebral arteries
      d.icd_code LIKE '434.%'     -- Other cerebral artery occlusion
    ))
    OR
    -- ICD-10 codes for cardiovascular complications
    (d.icd_version = 10 AND (
      d.icd_code LIKE 'I21.%' OR  -- Acute myocardial infarction
      d.icd_code LIKE 'I50.%' OR  -- Heart failure
      d.icd_code LIKE 'I63.%' OR  -- Cerebral infarction
      d.icd_code LIKE 'I64%'      -- Stroke, not specified as haemorrhage or infarction
    ))
),

-- Identify neurologic complications
neuro_complications AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    all_admissions a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    -- ICD-9 codes for neurologic complications
    (d.icd_version = 9 AND (
      d.icd_code LIKE '348.%' OR  -- Encephalopathy
      d.icd_code LIKE '433.%' OR  -- Occlusion and stenosis of cerebral arteries
      d.icd_code LIKE '434.%' OR  -- Other cerebral artery occlusion
      d.icd_code LIKE '436%'      -- Acute cerebrovascular disease
    ))
    OR
    -- ICD-10 codes for neurologic complications
    (d.icd_version = 10 AND (
      d.icd_code LIKE 'G93.%' OR  -- Other disorders of brain
      d.icd_code LIKE 'I63.%' OR  -- Cerebral infarction
      d.icd_code LIKE 'I64%'      -- Stroke, not specified as haemorrhage or infarction
    ))
),

-- Combine all data for analysis
final_data AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.anchor_age,
    a.los_days,
    a.mortality_30day,
    CASE WHEN d.subject_id IS NOT NULL THEN 1 ELSE 0 END AS is_dka,
    rs.sapsii_score,
    CASE WHEN cc.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_cardio_complication,
    CASE WHEN nc.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_neuro_complication
  FROM
    all_admissions a
  LEFT JOIN
    dka_patients d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  LEFT JOIN
    risk_scores rs ON a.subject_id = rs.subject_id AND a.hadm_id = rs.hadm_id
  LEFT JOIN
    cardio_complications cc ON a.subject_id = cc.subject_id AND a.hadm_id = cc.hadm_id
  LEFT JOIN
    neuro_complications nc ON a.subject_id = nc.subject_id AND a.hadm_id = nc.hadm_id
  WHERE
    a.los_days IS NOT NULL
),

-- Group data by DKA status
grouped_data AS (
  SELECT
    is_dka,
    COUNT(*) AS patient_count,
    AVG(sapsii_score) AS mean_risk_score,
    SUM(mortality_30day) * 100.0 / COUNT(*) AS mortality_30day_percent,
    SUM(has_cardio_complication) * 100.0 / COUNT(*) AS cardio_complication_percent,
    SUM(has_neuro_complication) * 100.0 / COUNT(*) AS neuro_complication_percent,
    AVG(los_days) AS mean_los_days,
    -- Collect all sapsii_scores for percentile calculation
    ARRAY_AGG(sapsii_score) AS sapsii_scores
  FROM
    final_data
  GROUP BY
    is_dka
),

-- Calculate percentiles
final_results AS (
  SELECT
    is_dka,
    patient_count,
    mean_risk_score,
    mortality_30day_percent,
    cardio_complication_percent,
    neuro_complication_percent,
    mean_los_days,
    -- Calculate percentiles from the array
    PERCENTILE_CONT(UNNEST(sapsii_scores), 0.5) OVER() AS overall_median_risk_score,
    PERCENTILE_CONT(CASE WHEN is_dka = 1 THEN UNNEST(sapsii_scores) END, 0.5) OVER() AS dka_median_risk_score,
    PERCENTILE_CONT(CASE WHEN is_dka = 0 THEN UNNEST(sapsii_scores) END, 0.5) OVER() AS non_dka_median_risk_score
  FROM
    grouped_data
)

-- Final output
SELECT * FROM final_results
ORDER BY is_dka;