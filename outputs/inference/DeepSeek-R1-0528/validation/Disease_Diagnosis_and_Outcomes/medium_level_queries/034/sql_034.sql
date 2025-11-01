WITH cohort AS (
  SELECT 
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 70 AND 80
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      WHERE 
        adm.hadm_id = diag.hadm_id 
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '428%') 
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
        )
    )
),
los_groups AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN los_days < 8 THEN '<8' 
      ELSE '>=8' 
    END AS los_group,
    hospital_expire_flag,
    -- Compute time-to-death in fractional days for non-survivors
    CASE 
      WHEN hospital_expire_flag = 1 THEN 
        TIMESTAMP_DIFF(deathtime, admittime, SECOND) / 86400.0
    END AS time_to_death_days
  FROM cohort
),
summary AS (
  SELECT 
    los_group,
    COUNT(hadm_id) AS n_admissions,
    SUM(hospital_expire_flag) AS n_deaths,
    ROUND(SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(hadm_id)) * 100, 2) AS mortality_rate_percent
  FROM los_groups
  GROUP BY los_group
),
non_survivors_median AS (
  SELECT 
    los_group,
    APPROX_QUANTILES(time_to_death_days, 100)[OFFSET(50)] AS median_time_to_death_days
  FROM los_groups
  WHERE hospital_expire_flag = 1
  GROUP BY los_group
)
SELECT 
  s.los_group,
  s.n_admissions,
  s.n_deaths,
  s.mortality_rate_percent,
  ROUND(n.median_time_to_death_days, 2) AS median_time_to_death_days
FROM summary s
LEFT JOIN non_survivors_median n
  ON s.los_group = n.los_group
ORDER BY s.los_group;