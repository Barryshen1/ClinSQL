WITH eligible_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.transfers` t
      WHERE t.hadm_id = a.hadm_id
        AND t.careunit NOT LIKE '%ICU%'
        AND (t.careunit LIKE '%WARD%' OR t.careunit LIKE '%FLOOR%')
    )
),
stratified_data AS (
  SELECT 
    a.hadm_id,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
      WHEN a.discharge_location IN (
        'Discharge, Home w/ Home Health', 
        'Discharged to home', 
        'Discharged to home with home health service', 
        'Home health care', 
        'Home', 
        'Home w/ HH', 
        'SNF-SNF', 
        'SNF', 
        'Short-term hospital', 
        'Against medical advice', 
        'Discharged to home health care', 
        'Discharged to self', 
        'Discharged/transferred to home under care of organized home health service organization', 
        'Discharged/transferred to home with home health service', 
        'Discharged/transferred to home with self care (discharge to home; homebound)', 
        'Left against medical advice', 
        'Discharged to home (routine discharge)', 
        'Discharged to home or self care', 
        'Discharged to home, self care (routine discharge)'
      ) THEN 'Discharged Home'
      WHEN a.discharge_location LIKE '%Hospice%' OR a.discharge_location LIKE '%hospice%'
        THEN 'Discharged to Hospice'
      ELSE NULL
    END AS stratum,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM eligible_admissions ea
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ea.hadm_id = a.hadm_id
)
SELECT 
  stratum,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV_SAMP(los_days), 2) AS sd_los_days,
  COUNT(*) AS n_patients
FROM stratified_data
WHERE stratum IS NOT NULL
GROUP BY stratum
ORDER BY 
  CASE stratum
    WHEN 'Discharged Home' THEN 1
    WHEN 'Discharged to Hospice' THEN 2
    WHEN 'In-Hospital Mortality' THEN 3
  END;