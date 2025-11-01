WITH first_admissions_raw AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS row_num
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.admission_type = 'ELECTIVE'
    AND a.hospital_expire_flag = 0
    AND a.dischtime > a.admittime
)
SELECT 
  STDDEV(los_days) AS sd_los_days
FROM 
  first_admissions_raw
WHERE 
  row_num = 1;