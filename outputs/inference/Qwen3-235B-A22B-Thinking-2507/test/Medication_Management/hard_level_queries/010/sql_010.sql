WITH base_cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 61 AND 71
),

complexity AS (
  SELECT 
    b.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM base_cohort b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON b.hadm_id = pr.hadm_id
    AND pr.starttime >= b.admittime
    AND pr.starttime <= DATETIME_ADD(b.admittime, INTERVAL 24 HOUR)
  GROUP BY b.hadm_id
),

admissions_with_los AS (
  SELECT 
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    DATETIME_DIFF(dischtime, admittime, SECOND) / (24*60*60) AS los_days
  FROM base_cohort
),

admissions_with_next AS (
  SELECT 
    *,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM admissions_with_los
),

admissions_with_readmission AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 0
      WHEN next_admittime IS NOT NULL AND next_admittime <= DATETIME_ADD(dischtime, INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS readmission_30d
  FROM admissions_with_next
),

full_data AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    COALESCE(c.complexity_score, 0) AS complexity_score,
    a.los_days,
    a.hospital_expire_flag,
    a.readmission_30d
  FROM admissions_with_readmission a
  LEFT JOIN complexity c
    ON a.hadm_id = c.hadm_id
),

quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY complexity_score) AS quintile
  FROM full_data
)

SELECT 
  quintile,
  COUNT(*) AS num_patients,
  AVG(complexity_score) AS mean_complexity_score,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) AS in_hospital_mortality,
  AVG(readmission_30d) AS readmission_30d_rate
FROM quintiles
GROUP BY quintile
ORDER BY quintile;