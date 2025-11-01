WITH acute_decompensated_hf AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.admittime, 
                   DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), 
                            INTERVAL p.anchor_age YEAR), 
                   YEAR) AS age_at_admission,
    DATEDIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE)) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  WHERE 
    p.gender = 'F'
    AND TIMESTAMP_DIFF(a.admittime, 
                       DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), 
                                INTERVAL p.anchor_age YEAR), 
                       YEAR) BETWEEN 80 AND 90
    AND d.icd_code IN ('I50.2', 'I50.3', 'I50.9')
    AND d.icd_version = 10
    AND a.dischtime IS NOT NULL
),
admissions_with_death_time AS (
  SELECT 
    hadm_id,
    los_days,
    hospital_expire_flag AS died,
    CASE 
      WHEN hospital_expire_flag = 1 THEN DATEDIFF(deathtime, admittime)
      ELSE NULL 
    END AS time_to_death_days
  FROM acute_decompensated_hf
),
los_categories AS (
  SELECT 
    hadm_id,
    los_days,
    died,
    time_to_death_days,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN los_days >= 8 THEN '>=8 days'
      ELSE 'Other'
    END AS los_category
  FROM admissions_with_death_time
),
grouped_mortality AS (
  SELECT 
    los_category,
    COUNT(*) AS n,
    SUM(died) AS d,
    SUM(died) / COUNT(*) AS mortality_rate,
    (SUM(died) / COUNT(*)) - 1.96 * SQRT((SUM(died)/COUNT(*)) * (1 - (SUM(died)/COUNT(*))) / COUNT(*)) AS lower_ci,
    (SUM(died) / COUNT(*)) + 1.96 * SQRT((SUM(died)/COUNT(*)) * (1 - (SUM(died)/COUNT(*))) / COUNT(*)) AS upper_ci
  FROM los_categories
  GROUP BY los_category
),
median_death AS (
  SELECT 
    los_category,
    APPROX_QUANTILES(time_to_death_days, 100)[OFFSET(50)] AS median_time_to_death
  FROM los_categories
  WHERE died = 1
  GROUP BY los_category
)
SELECT 
  g.los_category,
  g.n,
  g.d,
  g.mortality_rate,
  g.lower_ci,
  g.upper_ci,
  m.median_time_to_death
FROM grouped_mortality g
LEFT JOIN median_death m ON g.los_category = m.los_category
ORDER BY 
  CASE los_category
    WHEN '1-3 days' THEN 1
    WHEN '4-7 days' THEN 2
    WHEN '>=8 days' THEN 3
    ELSE 4
  END;