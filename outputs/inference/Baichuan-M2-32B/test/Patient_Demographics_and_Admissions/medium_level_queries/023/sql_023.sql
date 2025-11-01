WITH patient_birth AS (
  SELECT 
    subject_id,
    DATE_SUB(CAST(CONCAT(anchor_year, '-01-01') AS DATE), INTERVAL anchor_age YEAR) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
),
admissions_with_age AS (
  SELECT 
    a.*,
    TIMESTAMP_DIFF(a.admittime, p.birth_date, YEAR) AS age_at_admission,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN a.discharge_location LIKE '%Home%' THEN 'home'
      ELSE 'facility'
    END AS discharge_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patient_birth p ON a.subject_id = p.subject_id
  WHERE 
    a.admission_type = 'Emergency'
    AND TIMESTAMP_DIFF(a.admittime, p.birth_date, YEAR) BETWEEN 41 AND 51
),
cohort AS (
  SELECT 
    *,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM admissions_with_age
  WHERE dischtime IS NOT NULL
),
overall_percentile AS (
  SELECT 
    (COUNT(CASE WHEN los_days <= 10 THEN 1 END) * 100.0 / COUNT(*)) AS percentile_rank_10
  FROM cohort
),
category_stats AS (
  SELECT 
    discharge_category,
    COUNT(*) AS total_admissions,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS count_los_ge_7,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS proportion_los_ge_7
  FROM cohort
  GROUP BY discharge_category
)
SELECT 
  cs.discharge_category,
  cs.proportion_los_ge_7,
  op.percentile_rank_10
FROM category_stats cs
CROSS JOIN overall_percentile op
ORDER BY cs.discharge_category;