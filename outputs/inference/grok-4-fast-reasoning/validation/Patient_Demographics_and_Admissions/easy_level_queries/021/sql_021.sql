WITH first_admissions AS (
  SELECT 
    subject_id, 
    hadm_id AS first_hadm_id,
    admittime AS first_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
  WHERE a1.admittime = (
    SELECT MIN(a2.admittime)
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
    WHERE a2.subject_id = a1.subject_id
  )
)
SELECT 
  ROUND(COUNTIF(hospital_expire_flag = 1) * 100.0 / COUNT(*), 2) AS in_hospital_mortality_pct
FROM (
  SELECT DISTINCT 
    p.subject_id, 
    a.hospital_expire_flag
  FROM first_admissions fa
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON fa.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON fa.first_hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 83 AND 93
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON di.icd_code = dd.icd_code 
        AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = fa.first_hadm_id
        AND LOWER(dd.long_title) LIKE '%pneumonia%'
    )
);