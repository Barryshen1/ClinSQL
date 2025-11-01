WITH
-- Get male patients aged 51-61 with diabetes and acute heart failure
patient_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON diag.icd_code = d.icd_code
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND (
      -- Diabetes ICD codes (E11-E14)
      (diag.icd_code LIKE 'E11%' OR diag.icd_code LIKE 'E12%' OR diag.icd_code LIKE 'E13%' OR diag.icd_code LIKE 'E14%')
      -- Acute heart failure ICD codes (I50.9, I50.1, etc.)
      OR (diag.icd_code LIKE 'I50%')
    )
),

-- Get insulin regimens in first 24 hours
first_24h_regimens AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    MAX(CASE WHEN ph.sliding_scale = 'Y' THEN 1 ELSE 0 END) AS has_sliding_scale,
    MAX(CASE WHEN ph.basal_rate IS NOT NULL THEN 1 ELSE 0 END) AS has_basal,
    MAX(CASE WHEN ph.infusion_type = 'Bolus' THEN 1 ELSE 0 END) AS has_bolus
  FROM
    patient_cohort pc
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph ON pc.hadm_id = ph.hadm_id
    AND ph.starttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 24 HOUR)
  GROUP BY
    pc.subject_id, pc.hadm_id
),

-- Get insulin regimens in final 12 hours
final_12h_regimens AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    MAX(CASE WHEN ph.sliding_scale = 'Y' THEN 1 ELSE 0 END) AS has_sliding_scale,
    MAX(CASE WHEN ph.basal_rate IS NOT NULL THEN 1 ELSE 0 END) AS has_basal,
    MAX(CASE WHEN ph.infusion_type = 'Bolus' THEN 1 ELSE 0 END) AS has_bolus
  FROM
    patient_cohort pc
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph ON pc.hadm_id = ph.hadm_id
    AND ph.starttime BETWEEN TIMESTAMP_SUB(pc.dischtime, INTERVAL 12 HOUR) AND pc.dischtime
  GROUP BY
    pc.subject_id, pc.hadm_id
),

-- Classify regimen types for first 24 hours
first_24h_classification AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN has_basal = 1 AND has_bolus = 1 THEN 'Basal-Bolus'
      WHEN has_basal = 1 THEN 'Basal'
      WHEN has_bolus = 1 THEN 'Bolus'
      WHEN has_sliding_scale = 1 THEN 'Sliding-Scale'
      ELSE 'None'
    END AS regimen_type
  FROM
    first_24h_regimens
),

-- Classify regimen types for final 12 hours
final_12h_classification AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN has_basal = 1 AND has_bolus = 1 THEN 'Basal-Bolus'
      WHEN has_basal = 1 THEN 'Basal'
      WHEN has_bolus = 1 THEN 'Bolus'
      WHEN has_sliding_scale = 1 THEN 'Sliding-Scale'
      ELSE 'None'
    END AS regimen_type
  FROM
    final_12h_regimens
),

-- Count regimen types in first 24 hours
first_24h_counts AS (
  SELECT
    regimen_type,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM
    first_24h_classification
  GROUP BY
    regimen_type
),

-- Count regimen types in final 12 hours
final_12h_counts AS (
  SELECT
    regimen_type,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM
    final_12h_classification
  GROUP BY
    regimen_type
),

-- Get total patient counts for each period
total_counts AS (
  SELECT
    COUNT(DISTINCT subject_id) AS total_first_24h,
    (SELECT COUNT(DISTINCT subject_id) FROM final_12h_classification) AS total_final_12h
  FROM
    first_24h_classification
)

-- Final result with prevalence and percentage-point changes
SELECT
  f.regimen_type,
  f.patient_count AS first_24h_count,
  ROUND(f.patient_count * 100.0 / t.total_first_24h, 2) AS first_24h_prevalence,
  fl.patient_count AS final_12h_count,
  ROUND(fl.patient_count * 100.0 / t.total_final_12h, 2) AS final_12h_prevalence,
  ROUND((fl.patient_count * 100.0 / t.total_final_12h) - (f.patient_count * 100.0 / t.total_first_24h), 2) AS pct_point_change
FROM
  first_24h_counts f
JOIN
  final_12h_counts fl ON f.regimen_type = fl.regimen_type
JOIN
  total_counts t ON 1=1
ORDER BY
  f.regimen_type;