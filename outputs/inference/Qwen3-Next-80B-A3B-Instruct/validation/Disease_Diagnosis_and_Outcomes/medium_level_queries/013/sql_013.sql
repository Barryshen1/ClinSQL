WITH adhf_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND dicd.long_title ILIKE '%heart failure%'
    AND dicd.long_title ILIKE '%acute%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
los_groups AS (
  SELECT *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN los_days >= 8 THEN '8+ days'
      ELSE 'Unknown'
    END AS los_group
  FROM adhf_patients
  WHERE los_days >= 1
),
mortality_stats AS (
  SELECT
    los_group,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    AVG(hospital_expire_flag) * 100 AS mortality_percent,
    -- 95% CI using normal approximation
    (AVG(hospital_expire_flag) - 1.96 * SQRT(AVG(hospital_expire_flag) * (1 - AVG(hospital_expire_flag)) / COUNT(*))) * 100 AS ci_lower,
    (AVG(hospital_expire_flag) + 1.96 * SQRT(AVG(hospital_expire_flag) * (1 - AVG(hospital_expire_flag)) / COUNT(*))) * 100 AS ci_upper,
    -- Median time to death (only for deceased patients)
    PERCENTILE_CONT(CASE WHEN hospital_expire_flag = 1 THEN DATE_DIFF(deathtime, admittime, DAY) END, 0.5) AS median_time_to_death_days
  FROM los_groups
  GROUP BY los_group
)
SELECT
  los_group,
  total_patients,
  deaths,
  ROUND(mortality_percent, 2) AS mortality_percent,
  ROUND(ci_lower, 2) AS ci_lower,
  ROUND(ci_upper, 2) AS ci_upper,
  ROUND(median_time_to_death_days, 1) AS median_time_to_death_days
FROM mortality_stats
WHERE los_group != 'Unknown'
ORDER BY los_group;