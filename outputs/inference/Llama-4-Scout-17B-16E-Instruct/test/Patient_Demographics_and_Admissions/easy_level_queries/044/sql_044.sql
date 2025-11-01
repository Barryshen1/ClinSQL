WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
)
SELECT 
  APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(25)] AS percentile_25_mortality
FROM 
  eligible_patients;