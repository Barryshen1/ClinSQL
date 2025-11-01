WITH base_patients AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_adm,
    -- Calculate length of stay in days
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_adm
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
sepsis_without_shock AS (
  -- Sepsis codes (without shock)
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND (icd_code LIKE '038%' OR icd_code IN ('99591','99592')))
    OR 
    (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code = 'R6520'))
  EXCEPT DISTINCT
  -- Exclude septic shock codes
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code = '78552') 
    OR (icd_version = 10 AND icd_code = 'R6521')
),
cohort AS (
  SELECT 
    b.*,
    CASE 
      WHEN b.los_adm BETWEEN 1 AND 3 THEN '1-3'
      WHEN b.los_adm BETWEEN 4 AND 7 THEN '4-7'
      ELSE 'other'
    END AS los_group
  FROM base_patients b
  INNER JOIN sepsis_without_shock s
    ON b.hadm_id = s.hadm_id
  WHERE 
    b.age_adm BETWEEN 87 AND 97
    AND b.los_adm BETWEEN 1 AND 7  -- Only include 1-7 day stays
),
procedures_count AS (
  SELECT 
    hadm_id, 
    COUNT(*) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
)
SELECT 
  c.los_group,
  AVG(COALESCE(p.num_procedures, 0)) AS mean_diagnostic_procedures
FROM cohort c
LEFT JOIN procedures_count p
  ON c.hadm_id = p.hadm_id
WHERE c.los_group IN ('1-3', '4-7')  -- Filter relevant groups
GROUP BY c.los_group;