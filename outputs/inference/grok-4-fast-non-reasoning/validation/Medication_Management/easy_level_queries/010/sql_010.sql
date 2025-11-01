WITH nitrate_prescriptions AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    DATE_DIFF(DATE(pres.stoptime), DATE(pres.starttime), DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON p.subject_id = pres.subject_id 
    AND adm.hadm_id = pres.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND adm.hospital_expire_flag = 0
    AND LOWER(pres.drug) LIKE '%nitrate%'
    AND pres.stoptime IS NOT NULL
    AND pres.starttime IS NOT NULL
    AND pres.stoptime > pres.starttime
)
SELECT 
  STDDEV(duration_days) AS sd_nitrate_duration_days
FROM 
  nitrate_prescriptions
WHERE 
  duration_days > 0;