WITH cohort AS (
  -- Base cohort: males 56-66, inpatient, with diabetes and heart failure, non-expired
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN (
    -- Exists: at least one diabetes ICD-10
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = '10'
      AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E1[0-3]%')
  ) diabetes
    ON a.subject_id = diabetes.subject_id AND a.hadm_id = diabetes.hadm_id
  INNER JOIN (
    -- Exists: at least one heart failure ICD-10 (I50)
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = '10'
      AND icd_code LIKE 'I50%'
  ) hf
    ON a.subject_id = hf.subject_id AND a.hadm_id = hf.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT', 'OBSERVATION')
    AND a.hospital_expire_flag = 0
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),

first_48h_use AS (
  -- GLP-1 use in first 48h: from prescriptions or pharmacy
  SELECT DISTINCT c.subject_id
  FROM cohort c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    WHERE pres.subject_id = c.subject_id
      AND pres.hadm_id = c.hadm_id
      AND pres.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
      AND (LOWER(pres.drug) LIKE '%semaglutide%' 
           OR LOWER(pres.drug) LIKE '%liraglutide%' 
           OR LOWER(pres.drug) LIKE '%dulaglutide%'
           OR LOWER(pres.drug) LIKE '%exenatide%' 
           OR LOWER(pres.drug) LIKE '%tirzepatide%')
  )
  OR EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    WHERE ph.subject_id = c.subject_id
      AND ph.hadm_id = c.hadm_id
      AND ph.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
      AND (LOWER(ph.medication) LIKE '%semaglutide%' 
           OR LOWER(ph.medication) LIKE '%liraglutide%'
           OR LOWER(ph.medication) LIKE '%dulaglutide%' 
           OR LOWER(ph.medication) LIKE '%exenatide%'
           OR LOWER(ph.medication) LIKE '%tirzepatide%')
  )
),

final_24h_use AS (
  -- GLP-1 use in final 24h before discharge
  SELECT DISTINCT c.subject_id
  FROM cohort c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    WHERE pres.subject_id = c.subject_id
      AND pres.hadm_id = c.hadm_id
      AND pres.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
      AND (LOWER(pres.drug) LIKE '%semaglutide%' 
           OR LOWER(pres.drug) LIKE '%liraglutide%'
           OR LOWER(pres.drug) LIKE '%dulaglutide%' 
           OR LOWER(pres.drug) LIKE '%exenatide%'
           OR LOWER(pres.drug) LIKE '%tirzepatide%')
  )
  OR EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    WHERE ph.subject_id = c.subject_id
      AND ph.hadm_id = c.hadm_id
      AND ph.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
      AND (LOWER(ph.medication) LIKE '%semaglutide%' 
           OR LOWER(ph.medication) LIKE '%liraglutide%'
           OR LOWER(ph.medication) LIKE '%dulaglutide%' 
           OR LOWER(ph.medication) LIKE '%exenatide%'
           OR LOWER(ph.medication) LIKE '%tirzepatide%')
  )
),

summary AS (
  SELECT 
    COUNT(*) AS total_cohort,
    COUNT(DISTINCT f.subject_id) AS first_48h_users,
    COUNT(DISTINCT l.subject_id) AS final_24h_users,
    ROUND(COUNT(DISTINCT f.subject_id) * 100.0 / COUNT(*), 2) AS first_48h_prevalence_pct,
    ROUND(COUNT(DISTINCT l.subject_id) * 100.0 / COUNT(*), 2) AS final_24h_prevalence_pct,
    ROUND(
      (COUNT(DISTINCT l.subject_id) * 100.0 / COUNT(*) - COUNT(DISTINCT f.subject_id) * 100.0 / COUNT(*)), 
      2
    ) AS net_change_pct
  FROM cohort c
  LEFT JOIN first_48h_use f ON c.subject_id = f.subject_id
  LEFT JOIN final_24h_use l ON c.subject_id = l.subject_id
)

SELECT * FROM summary;