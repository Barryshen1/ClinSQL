WITH first_service AS (
  SELECT 
    hadm_id, 
    curr_service,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.services`
),
admissions_with_service AS (
  SELECT 
    a.*,
    fs.curr_service
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN first_service fs 
    ON a.hadm_id = fs.hadm_id AND fs.rn = 1
),
target_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.gender,  -- Corrected: now selecting from patients table
    p.anchor_age,
    a.admission_type,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    a.curr_service,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM admissions_with_service a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    a.curr_service = 'Medicine'
    AND a.admission_type != 'Elective'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),
discharge_categories AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'Home' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_category
  FROM target_admissions
)
SELECT 
  discharge_category,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
  SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS pct_rank_7_days
FROM discharge_categories
GROUP BY discharge_category
ORDER BY discharge_category;