WITH cohort AS (
  -- Base cohort: females 51-61 with diabetes and acute HF, inpatient, ICU stay
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND EXTRACT(YEAR FROM a.admittime) = p.anchor_year
    AND d.seq_num = 1  -- Primary diagnosis
    AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'I50%')  -- Diabetes (E10-E13) or Acute HF (I50)
    AND a.admission_type != 'OBSERVATION'  -- Inpatients only
),

insulin_events AS (
  -- Insulin administrations from ICU inputevents
  SELECT c.hadm_id, ie.starttime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie ON i.subject_id = ie.subject_id AND i.hadm_id = ie.hadm_id AND i.stay_id = ie.stay_id
  WHERE ie.itemid IN (225798, 225828, 225831, 225910, 500154, 500155)  -- Insulin itemids
    AND ie.amount IS NOT NULL AND ie.amount > 0
),

oral_prescriptions AS (
  -- Oral antidiabetic prescriptions (expanded common agents)
  SELECT c.hadm_id, pr.starttime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON c.hadm_id = pr.hadm_id
  WHERE (LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' 
         OR LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%repaglinide%'
         OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%dpp-4%'
         OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%canagliflozin%')
    AND (LOWER(pr.route) LIKE '%po%' OR LOWER(pr.route) LIKE '%oral%' OR pr.route IS NULL)  -- PO or unspecified (often oral)
),

insulin_status AS (
  -- Classify insulin per hadm_id (direct join to admissions for timing)
  SELECT 
    ie.hadm_id,
    MAX(CASE WHEN ie.starttime <= a.admittime + INTERVAL 48 HOUR THEN 1 ELSE 0 END) AS insulin_first48,
    MAX(CASE WHEN ie.starttime > a.dischtime - INTERVAL 24 HOUR AND ie.starttime <= a.dischtime THEN 1 ELSE 0 END) AS insulin_final24
  FROM insulin_events ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ie.hadm_id = a.hadm_id
  GROUP BY ie.hadm_id
),

oral_status AS (
  -- Classify oral per hadm_id (direct join to admissions for timing)
  SELECT 
    op.hadm_id,
    MAX(CASE WHEN op.starttime <= a.admittime + INTERVAL 48 HOUR THEN 1 ELSE 0 END) AS oral_first48,
    MAX(CASE WHEN op.starttime > a.dischtime - INTERVAL 24 HOUR AND op.starttime <= a.dischtime THEN 1 ELSE 0 END) AS oral_final24
  FROM oral_prescriptions op
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON op.hadm_id = a.hadm_id
  GROUP BY op.hadm_id
),

aggregated_status AS (
  SELECT 
    c.hadm_id,
    COALESCE(is.insulin_first48, 0) AS insulin_first48,
    COALESCE(is.insulin_final24, 0) AS insulin_final24,
    COALESCE(os.oral_first48, 0) AS oral_first48,
    COALESCE(os.oral_final24, 0) AS oral_final24
  FROM cohort c
  LEFT JOIN insulin_status is ON c.hadm_id = is.hadm_id
  LEFT JOIN oral_status os ON c.hadm_id = os.hadm_id
)

-- Final metrics
SELECT 
  'Insulin' AS medication_type,
  'First 48h' AS time_period,
  ROUND(AVG(insulin_first48) * 100, 2) AS percent_on_med,
  SUM(insulin_first48) AS count_on_first,
  NULL AS continued_count,
  NULL AS initiated_count,
  NULL AS discontinued_count
FROM aggregated_status
UNION ALL
SELECT 
  'Insulin', 
  'Final 24h', 
  ROUND(AVG(insulin_final24) * 100, 2),
  SUM(insulin_final24),
  NULL, NULL, NULL
FROM aggregated_status
UNION ALL
SELECT 
  'Insulin',
  'Transition Counts',
  NULL,
  NULL,
  SUM(CASE WHEN insulin_first48 = 1 AND insulin_final24 = 1 THEN 1 ELSE 0 END),  -- Continued
  SUM(CASE WHEN insulin_first48 = 0 AND insulin_final24 = 1 THEN 1 ELSE 0 END),  -- Initiated
  SUM(CASE WHEN insulin_first48 = 1 AND insulin_final24 = 0 THEN 1 ELSE 0 END)   -- Discontinued
FROM aggregated_status
UNION ALL
SELECT 
  'Oral Agents' AS medication_type,
  'First 48h' AS time_period,
  ROUND(AVG(oral_first48) * 100, 2) AS percent_on_med,
  SUM(oral_first48) AS count_on_first,
  NULL, NULL, NULL
FROM aggregated_status
UNION ALL
SELECT 
  'Oral Agents', 
  'Final 24h', 
  ROUND(AVG(oral_final24) * 100, 2),
  SUM(oral_final24),
  NULL, NULL, NULL
FROM aggregated_status
UNION ALL
SELECT 
  'Oral Agents',
  'Transition Counts',
  NULL,
  NULL,
  SUM(CASE WHEN oral_first48 = 1 AND oral_final24 = 1 THEN 1 ELSE 0 END),
  SUM(CASE WHEN oral_first48 = 0 AND oral_final24 = 1 THEN 1 ELSE 0 END),
  SUM(CASE WHEN oral_first48 = 1 AND oral_final24 = 0 THEN 1 ELSE 0 END)
FROM aggregated_status;