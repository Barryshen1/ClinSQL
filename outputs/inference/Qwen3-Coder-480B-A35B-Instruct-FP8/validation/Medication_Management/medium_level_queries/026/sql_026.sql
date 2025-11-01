WITH target_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),

diabetes_hf_admissions AS (
  SELECT tp.hadm_id, tp.admittime, tp.dischtime
  FROM target_patients tp
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    ON tp.hadm_id = d1.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd1
    ON d1.icd_code = dicd1.icd_code AND d1.icd_version = dicd1.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON tp.hadm_id = d2.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd2
    ON d2.icd_code = dicd2.icd_code AND d2.icd_version = dicd2.icd_version
  WHERE (
      (dicd1.icd_code = '25000' AND dicd1.icd_version = 9) OR
      (dicd1.icd_code = 'E119' AND dicd1.icd_version = 10)
    )
    AND (
      (dicd2.icd_code = '4280' AND dicd2.icd_version = 9) OR
      (dicd2.icd_code = 'I509' AND dicd2.icd_version = 10)
    )
    AND d1.hadm_id = d2.hadm_id
),

meds_first_72h AS (
  SELECT DISTINCT p.hadm_id,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(p.drug_type) IN ('main', 'base') AND LOWER(p.drug) NOT LIKE '%insulin%' THEN 'oral'
    END AS agent_type
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN diabetes_hf_admissions dha ON p.hadm_id = dha.hadm_id
  WHERE p.starttime BETWEEN dha.admittime AND dha.admittime + INTERVAL 72 HOUR
    AND p.drug IS NOT NULL
),

meds_last_72h AS (
  SELECT DISTINCT p.hadm_id,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(p.drug_type) IN ('main', 'base') AND LOWER(p.drug) NOT LIKE '%insulin%' THEN 'oral'
    END AS agent_type
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN diabetes_hf_admissions dha ON p.hadm_id = dha.hadm_id
  WHERE p.starttime BETWEEN dha.dischtime - INTERVAL 72 HOUR AND dha.dischtime
    AND p.drug IS NOT NULL
),

first_72h_summary AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS total_admissions,
    COUNTIF(agent_type = 'insulin') AS insulin_first,
    COUNTIF(agent_type = 'oral') AS oral_first
  FROM (
    SELECT hadm_id, agent_type
    FROM meds_first_72h
    WHERE agent_type IN ('insulin', 'oral')
  )
),

last_72h_summary AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS total_admissions,
    COUNTIF(agent_type = 'insulin') AS insulin_last,
    COUNTIF(agent_type = 'oral') AS oral_last
  FROM (
    SELECT hadm_id, agent_type
    FROM meds_last_72h
    WHERE agent_type IN ('insulin', 'oral')
  )
)

SELECT
  'First 72 Hours' AS time_window,
  ROUND(SAFE_DIVIDE(insulin_first, total_admissions) * 100, 2) AS insulin_pct,
  ROUND(SAFE_DIVIDE(oral_first, total_admissions) * 100, 2) AS oral_pct
FROM first_72h_summary

UNION ALL

SELECT
  'Final 72 Hours' AS time_window,
  ROUND(SAFE_DIVIDE(insulin_last, total_admissions) * 100, 2) AS insulin_pct,
  ROUND(SAFE_DIVIDE(oral_last, total_admissions) * 100, 2) AS oral_pct
FROM last_72h_summary;