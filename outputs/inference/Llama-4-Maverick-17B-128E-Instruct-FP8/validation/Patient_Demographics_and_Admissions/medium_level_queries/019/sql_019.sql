WITH filtered_admissions AS (
  SELECT 
    adm.hadm_id,
    adm.admittime,
    COALESCE(adm.deathtime, adm.dischtime) AS discharge_time,
    CASE 
      WHEN adm.discharge_location = 'HOME' THEN 'Home'
      WHEN adm.discharge_location = 'HOSPICE' THEN 'Hospice'
      WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital death'
      ELSE NULL
    END AS discharge_disposition
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 63 AND 73
    AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
    AND (adm.discharge_location IN ('HOME', 'HOSPICE') OR adm.hospital_expire_flag = 1)
),
los_calculations AS (
  SELECT 
    discharge_disposition,
    DATETIME_DIFF(discharge_time, admittime, DAY) AS los_days
  FROM 
    filtered_admissions
)
SELECT 
  discharge_disposition,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS std_los
FROM 
  los_calculations
GROUP BY 
  discharge_disposition
ORDER BY 
  discharge_disposition;