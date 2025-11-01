WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    -- Compute LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND a.dischtime IS NOT NULL
    AND a.admittime <= a.dischtime  -- valid admission
),
aged_cohort AS (
  SELECT *
  FROM patient_admissions
  WHERE age_at_admit >= 75
    AND age_at_admit <= 85
),
categorized AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) = 'home' THEN 'Discharged home'
      WHEN LOWER(discharge_location) IN (
        'short term hospital', 'skilled nursing facility', 'nursing home',
        'intermediate care', 'federal health care facility', 'psychiatric hospital',
        'rehabilitation facility'
      ) THEN 'Discharged to facility'
      ELSE 'Other'
    END AS discharge_group
  FROM aged_cohort
  WHERE discharge_location IS NOT NULL
),
summary_stats AS (
  SELECT
    discharge_group,
    -- Proportion with LOS >= 7 days
    AVG(CASE WHEN los_days >= 7 THEN 1.0 ELSE 0.0 END) AS prop_los_ge7,
    -- Count statistics for percentile rank of 7-day LOS
    COUNT(*) AS n,
    SUM(CASE WHEN los_days < 7 THEN 1 ELSE 0 END) AS count_less_than_7,
    SUM(CASE WHEN los_days = 7 THEN 1 ELSE 0 END) AS count_equal_7
  FROM categorized
  GROUP BY discharge_group
)
SELECT
  discharge_group,
  ROUND(prop_los_ge7, 3) AS proportion_los_ge7_days,
  ROUND(
    (count_less_than_7 + 0.5 * count_equal_7) / n * 100, 
    1
  ) AS percentile_rank_of_7_days
FROM summary_stats
ORDER BY discharge_group;