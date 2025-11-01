WITH
-- Define acute pancreatitis ICD codes
ap_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'K85.%'
),

-- Get male inpatients aged 63-73 with AP
ap_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN ap_icd_codes ap ON d.icd_code = ap.icd_code
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.admission_type != 'NEWBORN'
),

-- Get relevant lab items for instability score with standard reference ranges
lab_items AS (
  SELECT
    itemid,
    label,
    CASE
      WHEN label = 'White Blood Cells' THEN STRUCT(4.0 AS lower, 11.0 AS upper)
      WHEN label = 'Creatinine' THEN STRUCT(0.6 AS lower, 1.2 AS upper)
      WHEN label = 'Glucose' THEN STRUCT(70 AS lower, 99 AS upper)
      WHEN label = 'Potassium' THEN STRUCT(3.5 AS lower, 5.0 AS upper)
      WHEN label = 'Sodium' THEN STRUCT(135 AS lower, 145 AS upper)
      WHEN label = 'BUN' THEN STRUCT(8 AS lower, 20 AS upper)
      WHEN label = 'Hematocrit' THEN STRUCT(38.8 AS lower, 50.0 AS upper)
      WHEN label = 'Platelet Count' THEN STRUCT(150 AS lower, 450 AS upper)
      WHEN label = 'PT' THEN STRUCT(11.0 AS lower, 13.5 AS upper)
      WHEN label = 'PTT' THEN STRUCT(25.0 AS lower, 35.0 AS upper)
    END AS ref_range
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label IN (
    'White Blood Cells', 'Creatinine', 'Glucose', 'Potassium',
    'Sodium', 'BUN', 'Hematocrit', 'Platelet Count', 'PT', 'PTT'
  )
),

-- Get lab results within 72 hours of admission
early_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.valueuom,
    li.ref_range.lower AS ref_range_lower,
    li.ref_range.upper AS ref_range_upper,
    CASE
      WHEN l.valuenum < CAST(li.ref_range.lower AS FLOAT64) OR l.valuenum > CAST(li.ref_range.upper AS FLOAT64) THEN 1
      ELSE 0
    END AS is_abnormal
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN ap_patients a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  JOIN lab_items li ON l.itemid = li.itemid
  WHERE
    TIMESTAMP_DIFF(l.charttime, a.admittime, HOUR) BETWEEN 0 AND 72
),

-- Calculate lab instability score per patient
patient_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(is_abnormal) AS lab_instability_score,
    COUNT(DISTINCT itemid) AS total_lab_types,
    SUM(is_abnormal) / COUNT(DISTINCT itemid) AS critical_rate
  FROM early_labs
  GROUP BY subject_id, hadm_id
),

-- Calculate 90th percentile score
score_percentiles AS (
  SELECT PERCENTILE_CONT(lab_instability_score, 0.9) OVER() AS p90_score
  FROM patient_scores
  LIMIT 1
),

-- Get general inpatient comparison group (all male 63-73)
general_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.admission_type != 'NEWBORN'
)

-- Final comparison
SELECT
  'Patients with AP and score ≥P90' AS group_name,
  COUNT(DISTINCT ps.subject_id) AS patient_count,
  SUM(CASE WHEN a.hospital_expire_flag THEN 1 ELSE 0 END) / COUNT(DISTINCT ps.subject_id) AS mortality_rate,
  AVG(ps.los_hours) AS mean_los_hours,
  AVG(ps.critical_rate) AS mean_critical_rate
FROM patient_scores ps
JOIN ap_patients a ON ps.subject_id = a.subject_id AND ps.hadm_id = a.hadm_id
CROSS JOIN score_percentiles sp
WHERE ps.lab_instability_score >= sp.p90_score

UNION ALL

SELECT
  'General inpatients (male 63-73)' AS group_name,
  COUNT(DISTINCT gi.subject_id) AS patient_count,
  SUM(CASE WHEN gi.hospital_expire_flag THEN 1 ELSE 0 END) / COUNT(DISTINCT gi.subject_id) AS mortality_rate,
  AVG(gi.los_hours) AS mean_los_hours,
  NULL AS mean_critical_rate  -- Not calculated for general inpatients
FROM general_inpatients gi;