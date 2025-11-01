WITH heart_failure_admissions AS (
  -- Get admissions with heart failure diagnosis for female patients aged 70-80
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN a.deathtime IS NOT NULL THEN TIMESTAMP_DIFF(a.deathtime, a.admittime, HOUR) ELSE NULL END AS time_to_death_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND d.icd_code LIKE 'I50.%'  -- Heart failure ICD-10 codes
    AND a.hospital_expire_flag IS NOT NULL  -- Ensure we have mortality data
),

los_groups AS (
  -- Categorize admissions by LOS and calculate metrics
  SELECT
    CASE WHEN los_days < 8 THEN '<8 days' ELSE '>=8 days' END AS los_group,
    COUNT(DISTINCT hadm_id) AS admission_count,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS death_count,
    ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT hadm_id) * 100, 2) AS mortality_rate,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 1 THEN time_to_death_hours ELSE NULL END, 100)[OFFSET(50)] AS median_time_to_death_hours
  FROM
    heart_failure_admissions
  GROUP BY
    los_group
)

-- Final output
SELECT
  los_group,
  admission_count AS N,
  mortality_rate AS mortality_rate_percent,
  median_time_to_death_hours / 24 AS median_time_to_death_days
FROM
  los_groups
ORDER BY
  los_group;