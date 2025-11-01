WITH 
-- Step 1: Filter patients based on age and gender
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 49 AND 59
),

-- Step 2: Identify patients with sepsis
sepsis_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    WHERE d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version AND diag.long_title LIKE '%Sepsis%'
  )
  AND d.hadm_id IN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  )
),

-- Step 3: Calculate LOS and Day-1 ICU status
patient_characteristics AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS hospital_los,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE a.hadm_id = icu.hadm_id AND DATETIME_DIFF(icu.intime, a.admittime, HOUR) <= 24
      ) THEN 'ICU'
      ELSE 'non-ICU'
    END AS day1_icu_status,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.hadm_id IN (SELECT hadm_id FROM sepsis_patients) AND a.subject_id IN (SELECT subject_id FROM eligible_patients)
),

-- Step 4: Identify comorbidities
comorbidities_and_outcomes AS (
  SELECT 
    pc.hadm_id,
    pc.day1_icu_status,
    pc.hospital_los,
    pc.hospital_expire_flag,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = pc.hadm_id AND d.icd_code LIKE 'N18%'
    ) THEN 1 ELSE 0 END AS has_ckd,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = pc.hadm_id AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%')
    ) THEN 1 ELSE 0 END AS has_diabetes
  FROM patient_characteristics pc
)

-- Final analysis
SELECT 
  CASE WHEN hospital_los <= 5 THEN 'LOS <= 5' ELSE 'LOS > 5' END AS los_group,
  day1_icu_status,
  COUNT(*) AS N,
  SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_percent,
  SUM(has_ckd) * 100.0 / COUNT(*) AS ckd_prevalence,
  SUM(has_diabetes) * 100.0 / COUNT(*) AS diabetes_prevalence
FROM comorbidities_and_outcomes
GROUP BY los_group, day1_icu_status
ORDER BY los_group, day1_icu_status;