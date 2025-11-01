WITH 
-- Identify heart failure ICD codes
heart_failure_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%Heart failure%'
),

-- Identify CKD and diabetes ICD codes
ckd_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%Chronic kidney disease%'
),
diabetes_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%Diabetes mellitus%'
),

-- Patient data with admissions and comorbidities
patient_data AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    CASE 
      WHEN d.icd_code IN (SELECT icd_code FROM heart_failure_icd) THEN 1
      ELSE 0
    END AS has_heart_failure,
    CASE 
      WHEN d.icd_code IN (SELECT icd_code FROM ckd_icd) THEN 1
      ELSE 0
    END AS has_ckd,
    CASE 
      WHEN d.icd_code IN (SELECT icd_code FROM diabetes_icd) THEN 1
      ELSE 0
    END AS has_diabetes
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON 
    a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
)

-- Calculate comorbidity burden and LOS
SELECT 
  CASE 
    WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) <= 5 THEN '≤5'
    ELSE '>5'
  END AS los_category,
  CASE 
    WHEN (SUM(CASE WHEN has_ckd = 1 THEN 1 ELSE 0 END) + SUM(CASE WHEN has_diabetes = 1 THEN 1 ELSE 0 END)) = 0 THEN 'Low'
    WHEN (SUM(CASE WHEN has_ckd = 1 THEN 1 ELSE 0 END) + SUM(CASE WHEN has_diabetes = 1 THEN 1 ELSE 0 END)) = 1 THEN 'Med'
    ELSE 'High'
  END AS comorbidity_tertile,
  COUNT(hadm_id) AS N,
  SUM(hospital_expire_flag) AS deaths,
  SUM(hospital_expire_flag) * 1.0 / COUNT(hadm_id) AS mortality_rate
FROM 
  patient_data
WHERE 
  gender = 'F' AND anchor_age BETWEEN 39 AND 49 AND has_heart_failure = 1
GROUP BY 
  1, 2
ORDER BY 
  1, 2;