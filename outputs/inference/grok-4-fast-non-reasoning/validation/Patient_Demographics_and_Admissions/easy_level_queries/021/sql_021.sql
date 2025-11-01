WITH first_admissions AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.admission_type IN ('ELECTIVE', 'NEWBORN', 'URGENT', 'EMERGENCY')
),
pneumonia_cohort AS (
  SELECT 
    fa.*,
    di.icd_code,
    dd.long_title
  FROM first_admissions fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON fa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE 
    fa.rn = 1
    AND di.icd_version = 10
    AND di.icd_code LIKE 'J%'
)
SELECT 
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  ROUND((SUM(hospital_expire_flag) * 100.0 / COUNT(*)), 2) AS mortality_percentage
FROM pneumonia_cohort;