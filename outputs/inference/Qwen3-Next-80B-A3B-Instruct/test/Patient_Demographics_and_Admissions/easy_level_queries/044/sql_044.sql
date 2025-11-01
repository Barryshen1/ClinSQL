WITH first_admission AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime ASC) AS rn
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
)
SELECT 
  APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(25)] AS p25_inhospital_mortality
FROM 
  first_admission
WHERE 
  rn = 1;