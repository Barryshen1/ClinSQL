WITH cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
),
first_admissions AS (
  SELECT 
    a.subject_id,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime ASC) AS rn
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    cohort c ON a.subject_id = c.subject_id
)
SELECT 
  APPROX_QUANTILES(hospital_expire_flag, 4)[OFFSET(1)] AS p25_inhospital_mortality
FROM 
  first_admissions
WHERE 
  rn = 1;