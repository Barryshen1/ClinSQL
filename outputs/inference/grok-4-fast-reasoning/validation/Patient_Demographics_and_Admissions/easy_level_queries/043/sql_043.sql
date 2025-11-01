WITH eligible_admissions AS (
  SELECT 
    a.hadm_id, 
    a.hospital_expire_flag,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS approx_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 51 AND 61
)
SELECT 
  quantiles[OFFSET(1)] AS q1,
  quantiles[OFFSET(3)] AS q3,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr
FROM (
  SELECT APPROX_QUANTILES(hospital_expire_flag, 4) AS quantiles
  FROM eligible_admissions
);