WITH 
acs_admissions AS (
  SELECT 
    diag.hadm_id,
    MAX(CASE WHEN diag.seq_num = 1 THEN 1 ELSE 0 END) AS primary_acs
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  WHERE 
    (diag.icd_version = 9 AND (diag.icd_code LIKE '410%' OR diag.icd_code IN ('411.1', '411.81')))
    OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' OR diag.icd_code = 'I20.0'))
  GROUP BY diag.hadm_id
),
patient_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
admissions_with_acs AS (
  SELECT 
    pa.*,
    acs.primary_acs,
    -- Compute age at admission
    pa.anchor_age + (EXTRACT(YEAR FROM pa.admittime) - pa.anchor_year) AS age_at_admission
  FROM patient_admissions pa
  INNER JOIN acs_admissions acs
    ON pa.hadm_id = acs.hadm_id
  WHERE 
    pa.anchor_age + (EXTRACT(YEAR FROM pa.admittime) - pa.anchor_year) BETWEEN 50 AND 60
),
diag_procedures AS (
  SELECT 
    p.hadm_id, 
    COUNT(*) AS num_diag_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  WHERE 
    -- ICD-9 diagnostic procedures
    (p.icd_version = 9 AND (
        p.icd_code IN ('37.21', '37.22', '37.23')
        OR (p.icd_code >= '87.00' AND p.icd_code <= '88.99')
        OR (p.icd_code >= '89.20' AND p.icd_code <= '89.29')
        OR (p.icd_code >= '89.40' AND p.icd_code <= '89.59')
        OR (p.icd_code >= '89.60' AND p.icd_code <= '89.69')
    ))
    OR 
    -- ICD-10 diagnostic procedures (sections B or 3)
    (p.icd_version = 10 AND (p.icd_code LIKE 'B%' OR p.icd_code LIKE '3%'))
  GROUP BY p.hadm_id
),
admissions_with_procedures AS (
  SELECT 
    a.*,
    COALESCE(d.num_diag_procedures, 0) AS num_diag_procedures,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM admissions_with_acs a
  LEFT JOIN diag_procedures d
    ON a.hadm_id = d.hadm_id
),
los_groups AS (
  SELECT 
    *,
    CASE 
      WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE NULL 
    END AS los_group
  FROM admissions_with_procedures
  WHERE los BETWEEN 1 AND 8  -- Explicitly filter to 1-8 days
)

SELECT 
  los_group,
  CASE 
    WHEN primary_acs = 1 THEN 'Primary'
    ELSE 'Secondary'
  END AS acs_diagnosis_type,
  COUNT(*) AS num_admissions,
  APPROX_QUANTILES(num_diag_procedures, 4)[SAFE_OFFSET(1)] AS p25,
  APPROX_QUANTILES(num_diag_procedures, 4)[SAFE_OFFSET(2)] AS p50,
  APPROX_QUANTILES(num_diag_procedures, 4)[SAFE_OFFSET(3)] AS p75
FROM los_groups
WHERE los_group IS NOT NULL
GROUP BY los_group, acs_diagnosis_type
ORDER BY los_group, acs_diagnosis_type;