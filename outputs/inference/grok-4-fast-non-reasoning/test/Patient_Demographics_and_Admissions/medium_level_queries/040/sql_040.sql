WITH cohort AS (
  SELECT 
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.admission_type = 'SURG'
    AND a.dischtime IS NOT NULL  -- Exclude rare incomplete records
),
stratified AS (
  SELECT 
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
      WHEN discharge_location IN ('SNF', 'REHAB/DISTINCT PART HOSP', 'LTAC') THEN 'Facility (SNF/rehab/LTACH)'
      ELSE 'Other'  -- Rare cases (e.g., AMA); low proportion
    END AS discharge_category,
    los_days
  FROM 
    cohort
)
SELECT 
  discharge_category,
  ROUND(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) * 1.0 / COUNT(*), 4) AS prop_los_ge7,
  ROUND(SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) * 1.0 / COUNT(*), 4) AS prop_los_ge14,
  COUNT(*) AS total_admissions
FROM 
  stratified
GROUP BY 
  discharge_category
ORDER BY 
  total_admissions DESC;