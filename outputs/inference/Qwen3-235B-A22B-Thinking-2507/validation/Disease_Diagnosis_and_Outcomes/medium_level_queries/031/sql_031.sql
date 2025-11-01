WITH patient_condition AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Determine condition: sepsis or septic shock
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        WHERE d.hadm_id = a.hadm_id AND d.icd_code = 'R6521'
      ) THEN 'septic shock'
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        WHERE d.hadm_id = a.hadm_id 
          AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%' OR d.icd_code = 'R6520')
      ) THEN 'sepsis'
      ELSE NULL
    END AS condition
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND a.dischtime IS NOT NULL  -- Only include discharged patients
),

filtered_patients AS (
  SELECT *
  FROM patient_condition
  WHERE age_at_admission BETWEEN 53 AND 63
    AND condition IS NOT NULL
),

los_groups AS (
  SELECT 
    *,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE 
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) <= 7 THEN '≤7'
      ELSE '>7'
    END AS los_group,
    -- Time to death in days (for deceased patients only)
    CASE 
      WHEN hospital_expire_flag = 1 
      THEN DATETIME_DIFF(deathtime, admittime, HOUR) / 24.0 
      ELSE NULL 
    END AS time_to_death_days
  FROM filtered_patients
),

grouped_stats AS (
  SELECT 
    condition,
    los_group,
    COUNT(*) AS N,
    AVG(hospital_expire_flag) AS mortality_rate,
    APPROX_QUANTILES(IF(hospital_expire_flag = 1, time_to_death_days, NULL), 100)[OFFSET(50)] AS median_time_to_death_days
  FROM los_groups
  GROUP BY condition, los_group
),

-- Calculate differences within each LOS group
diffs AS (
  SELECT 
    los_group,
    MAX(CASE WHEN condition = 'septic shock' THEN mortality_rate END) -
    MAX(CASE WHEN condition = 'sepsis' THEN mortality_rate END) AS absolute_mortality_diff,
    (MAX(CASE WHEN condition = 'septic shock' THEN mortality_rate END) -
     MAX(CASE WHEN condition = 'sepsis' THEN mortality_rate END)) /
    NULLIF(MAX(CASE WHEN condition = 'sepsis' THEN mortality_rate END), 0) AS relative_mortality_diff
  FROM grouped_stats
  GROUP BY los_group
)

SELECT 
  gs.condition,
  gs.los_group,
  gs.N,
  gs.mortality_rate * 100 AS mortality_pct,
  gs.median_time_to_death_days,
  d.absolute_mortality_diff * 100 AS absolute_mortality_diff_pct,
  d.relative_mortality_diff
FROM grouped_stats gs
LEFT JOIN diffs d ON gs.los_group = d.los_group
ORDER BY gs.los_group, gs.condition;