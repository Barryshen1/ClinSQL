WITH first_admission AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS adm_rank
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 35 AND 45
),
cabg_patients AS (
  SELECT 
    f.subject_id, 
    f.hadm_id, 
    f.hospital_expire_flag
  FROM first_admission f
  WHERE 
    f.adm_rank = 1  -- first admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
      WHERE 
        p.subject_id = f.subject_id 
        AND p.hadm_id = f.hadm_id
        AND (
          (p.icd_version = 9 AND p.icd_code LIKE '36.1%')  -- CABG-specific ICD-9 codes
          OR 
          (p.icd_version = 10 AND p.icd_code LIKE '021%')   -- CABG-specific ICD-10 codes
        )
    )
)
SELECT 
  COUNT(subject_id) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(subject_id)) AS mortality_rate
FROM cabg_patients;