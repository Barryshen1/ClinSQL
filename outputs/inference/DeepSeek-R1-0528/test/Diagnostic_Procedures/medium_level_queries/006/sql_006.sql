WITH base_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    -- Calculate age at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission,
    -- Calculate LOS in days
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
),
sepsis_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('99591', '99592')) OR  -- Sepsis without shock (ICD-9)
    (icd_version = 10 AND icd_code IN ('A419', 'R6520'))    -- Sepsis without shock (ICD-10)
),
shock_exclusions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code = '78552') OR  -- Septic shock (ICD-9)
    (icd_version = 10 AND icd_code = 'R6521')    -- Septic shock (ICD-10)
),
cohort AS (
  SELECT 
    ba.subject_id, 
    ba.hadm_id, 
    ba.los_days,
    -- Categorize LOS
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8'
    END AS los_group,
    -- Determine ICU status
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
        WHERE icu.hadm_id = ba.hadm_id
      ) THEN 'ICU' 
      ELSE 'no ICU' 
    END AS icu_status
  FROM base_admissions ba
  INNER JOIN sepsis_admissions sep 
    ON ba.hadm_id = sep.hadm_id
  LEFT JOIN shock_exclusions ex 
    ON ba.hadm_id = ex.hadm_id
  WHERE 
    ex.hadm_id IS NULL  -- Exclude septic shock
    AND ba.age_at_admission BETWEEN 48 AND 58
    AND ba.los_days BETWEEN 1 AND 8  -- Only LOS 1-8 days
),
ultrasound_counts AS (
  SELECT 
    hadm_id,
    COUNT(*) AS num_ultrasounds
  FROM (
    -- Ultrasound procedures from ICD
    SELECT proc.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
      ON proc.icd_code = dip.icd_code AND proc.icd_version = dip.icd_version
    WHERE LOWER(dip.long_title) LIKE '%ultrasound%'
    UNION ALL
    -- Ultrasound procedures from HCPCS
    SELECT hcpc.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcpc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
      ON hcpc.hcpcs_cd = dh.code
    WHERE 
      LOWER(dh.long_description) LIKE '%ultrasound%' 
      OR LOWER(dh.short_description) LIKE '%ultrasound%'
  ) 
  GROUP BY hadm_id
)
SELECT 
  c.icu_status,
  c.los_group,
  COUNT(DISTINCT c.subject_id) AS patient_count,
  COUNT(c.hadm_id) AS admission_count,
  AVG(COALESCE(uc.num_ultrasounds, 0)) AS mean_ultrasounds_per_admission
FROM cohort c
LEFT JOIN ultrasound_counts uc
  ON c.hadm_id = uc.hadm_id
GROUP BY c.icu_status, c.los_group
ORDER BY c.icu_status, c.los_group;