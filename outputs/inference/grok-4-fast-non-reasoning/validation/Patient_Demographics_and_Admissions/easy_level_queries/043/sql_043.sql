WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
)
SELECT 
  APPROX_QUANTILES(mortality, 2)[OFFSET(1)] - APPROX_QUANTILES(mortality, 2)[OFFSET(0)] AS iqr_mortality
FROM (
  SELECT 
    hospital_expire_flag AS mortality
  FROM 
    eligible_admissions
);