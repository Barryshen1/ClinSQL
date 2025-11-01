WITH first_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
)
SELECT 
  COUNTIF(hospital_expire_flag = 1) * 100.0 / COUNT(*) AS mortality_rate
FROM first_admissions
WHERE rn = 1
  AND gender = 'F'
  AND (anchor_age + EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 83 AND 93
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE di.hadm_id = first_admissions.hadm_id
      AND LOWER(d.long_title) LIKE '%pneumonia%'
  );