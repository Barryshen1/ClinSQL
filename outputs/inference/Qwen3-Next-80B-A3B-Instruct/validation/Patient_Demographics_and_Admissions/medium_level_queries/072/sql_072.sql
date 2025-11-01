WITH first_service AS (
  SELECT 
    hadm_id,
    curr_service,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.services
),
filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN first_service fs
    ON a.hadm_id = fs.hadm_id AND fs.rn = 1
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND fs.curr_service = 'MED'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
stratified AS (
  SELECT 
    los_days,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
      ELSE NULL
    END AS discharge_category
  FROM filtered_admissions
  WHERE discharge_location IN ('HOME', 'HOSPICE') OR hospital_expire_flag = 1
)
SELECT 
  discharge_category,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  AVG(CASE WHEN los_days <= 5 THEN 1.0 ELSE 0 END) AS proportion_los_le_5
FROM stratified
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category
ORDER BY discharge_category;