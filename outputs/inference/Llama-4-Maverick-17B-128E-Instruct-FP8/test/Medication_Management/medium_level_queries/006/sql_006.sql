WITH patient_cohort AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 48 AND 58
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE icd_code LIKE 'E11%' AND icd_version = 10
  )
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE icd_code LIKE 'I50%' AND icd_version = 10
  )
  AND p.gender = 'F'  -- Adding the gender filter as per the clinical question
),
med_admin AS (
  SELECT pc.subject_id, pc.hadm_id, pc.admittime, pc.dischtime, 
         CASE 
           WHEN p.starttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 72 HOUR) THEN 1
           ELSE 0
         END AS glp1_first_72h,
         CASE 
           WHEN p.starttime BETWEEN TIMESTAMP_SUB(pc.dischtime, INTERVAL 48 HOUR) AND pc.dischtime THEN 1
           ELSE 0
         END AS glp1_last_48h
  FROM patient_cohort pc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON pc.hadm_id = p.hadm_id
  WHERE LOWER(p.drug) LIKE '%glp-1%'  -- Removed the reference to 'medication'
),
initiation_rates AS (
  SELECT 
    COUNT(CASE WHEN glp1_first_72h = 1 THEN hadm_id END) AS count_glp1_first_72h,
    COUNT(hadm_id) AS total_patients,
    COUNT(CASE WHEN glp1_last_48h = 1 THEN hadm_id END) AS count_glp1_last_48h
  FROM (
    SELECT hadm_id, MAX(glp1_first_72h) AS glp1_first_72h, MAX(glp1_last_48h) AS glp1_last_48h
    FROM med_admin
    GROUP BY hadm_id
  )
)
SELECT 
  SAFE_DIVIDE(count_glp1_first_72h, total_patients) * 100 AS initiation_rate_first_72h,
  SAFE_DIVIDE(count_glp1_last_48h, total_patients) * 100 AS initiation_rate_last_48h,
  (SAFE_DIVIDE(count_glp1_first_72h, total_patients) - SAFE_DIVIDE(count_glp1_last_48h, total_patients)) * 100 AS absolute_difference
FROM initiation_rates;