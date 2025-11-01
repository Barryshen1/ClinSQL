WITH patient_admissions AS (
  SELECT 
    hosp.subject_id,
    hosp.hadm_id,
    hosp.hospital_expire_flag,
    pats.gender,
    pats.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` hosp
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pats
  ON 
    hosp.subject_id = pats.subject_id
  WHERE 
    pats.gender = 'F'
    AND pats.anchor_age BETWEEN 51 AND 61
),
mortality_per_encounter AS (
  SELECT 
    hadm_id,
    hospital_expire_flag
  FROM 
    patient_admissions
)

SELECT 
  APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(25)] AS Q1,
  APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(75)] AS Q3
FROM 
  mortality_per_encounter;