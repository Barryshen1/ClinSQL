SELECT 
  PERCENTILE_DISC(hospital_expire_flag, 0.75) OVER() - 
  PERCENTILE_DISC(hospital_expire_flag, 0.25) OVER() AS iqr_mortality
FROM 
  physionet-data.mimiciv_3_1_hosp.admissions a
JOIN 
  physionet-data.mimiciv_3_1_hosp.patients p
  ON a.subject_id = p.subject_id
WHERE 
  p.gender = 'F' 
  AND p.anchor_age BETWEEN 51 AND 61
LIMIT 1;