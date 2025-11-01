WITH
-- Define diabetes and heart failure ICD codes
diabetes_codes AS (
  SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'E11%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%'
),
heart_failure_codes AS (
  SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I50%' OR icd_code = 'I11.0'
),

-- Get qualifying patients with both conditions
qualifying_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON a.hadm_id = d1.hadm_id
  JOIN diabetes_codes dc ON d1.icd_code = dc.icd_code
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a.hadm_id = d2.hadm_id
  JOIN heart_failure_codes hfc ON d2.icd_code = hfc.icd_code
  WHERE p.anchor_age BETWEEN 65 AND 75
    AND p.gender = 'F'
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 96
    AND d1.seq_num = 1  -- Primary diagnosis
    AND d2.seq_num = 1  -- Primary diagnosis
  GROUP BY 1, 2, 3, 4, 5, 6
),

-- Identify insulin regimens
insulin_regimens AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN LOWER(medication) LIKE '%basal%' AND LOWER(medication) LIKE '%bolus%' THEN 'basal-bolus'
      WHEN LOWER(medication) LIKE '%basal%' THEN 'basal'
      WHEN LOWER(medication) LIKE '%bolus%' THEN 'bolus'
      WHEN sliding_scale = 'Yes' THEN 'sliding-scale'
      ELSE NULL
    END AS regimen_type,
    starttime AS charttime  -- Fixed: replaced charttime with starttime for pharmacy
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE LOWER(medication) LIKE '%insulin%'

  UNION ALL

  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN LOWER(drug) LIKE '%basal%' AND LOWER(drug) LIKE '%bolus%' THEN 'basal-bolus'
      WHEN LOWER(drug) LIKE '%basal%' THEN 'basal'
      WHEN LOWER(drug) LIKE '%bolus%' THEN 'bolus'
      WHEN LOWER(drug) LIKE '%sliding%' THEN 'sliding-scale'
      ELSE NULL
    END AS regimen_type,
    starttime AS charttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%insulin%'

  UNION ALL

  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN LOWER(medication) LIKE '%basal%' AND LOWER(medication) LIKE '%bolus%' THEN 'basal-bolus'
      WHEN LOWER(medication) LIKE '%basal%' THEN 'basal'
      WHEN LOWER(medication) LIKE '%bolus%' THEN 'bolus'
      WHEN LOWER(medication) LIKE '%sliding%' THEN 'sliding-scale'
      ELSE NULL
    END AS regimen_type,
    charttime
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE LOWER(medication) LIKE '%insulin%'
),

-- Get regimen types for first 48h and last 48h
regimen_periods AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    MAX(CASE WHEN TIMESTAMP_DIFF(r.charttime, q.admittime, HOUR) <= 48 THEN r.regimen_type END) AS first_48h_regimen,
    MAX(CASE WHEN TIMESTAMP_DIFF(q.dischtime, r.charttime, HOUR) <= 48 THEN r.regimen_type END) AS last_48h_regimen
  FROM qualifying_patients q
  LEFT JOIN insulin_regimens r ON q.subject_id = r.subject_id AND q.hadm_id = r.hadm_id
  GROUP BY 1, 2
),

-- Count regimen types in each period
regimen_counts AS (
  SELECT
    'first_48h' AS period,
    regimen_type,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM regimen_periods
  CROSS JOIN UNNEST([first_48h_regimen]) AS regimen_type
  WHERE regimen_type IS NOT NULL
  GROUP BY 1, 2

  UNION ALL

  SELECT
    'last_48h' AS period,
    regimen_type,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM regimen_periods
  CROSS JOIN UNNEST([last_48h_regimen]) AS regimen_type
  WHERE regimen_type IS NOT NULL
  GROUP BY 1, 2
),

-- Count regimen transitions
regimen_transitions AS (
  SELECT
    first_48h_regimen AS from_regimen,
    last_48h_regimen AS to_regimen,
    COUNT(DISTINCT subject_id) AS transition_count
  FROM regimen_periods
  WHERE first_48h_regimen IS NOT NULL AND last_48h_regimen IS NOT NULL
  GROUP BY 1, 2
)

-- Final results
SELECT
  'regimen_distribution' AS metric_type,
  period,
  regimen_type,
  patient_count,
  ROUND(patient_count * 100.0 / SUM(patient_count) OVER (PARTITION BY period), 2) AS percentage
FROM regimen_counts

UNION ALL

SELECT
  'regimen_transitions' AS metric_type,
  CONCAT(from_regimen, '→', to_regimen) AS period,
  NULL AS regimen_type,
  transition_count AS patient_count,
  ROUND(transition_count * 100.0 / SUM(transition_count) OVER (), 2) AS percentage
FROM regimen_transitions
ORDER BY metric_type, period, regimen_type;