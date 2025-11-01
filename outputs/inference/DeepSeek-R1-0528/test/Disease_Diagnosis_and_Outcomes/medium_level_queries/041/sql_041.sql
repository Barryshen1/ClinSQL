WITH sepsis_without_shock AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
      (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^038') OR icd_code IN ('99591', '99592', '78552'))
      OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^A40|^A41') OR icd_code IN ('R6520', 'R6521'))
    )
    AND (icd_version, icd_code) NOT IN (
      (9, '78552'), (10, 'R6521')  -- Explicitly exclude septic shock codes
    )
),
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM sepsis_without_shock s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 50 AND 60
),
cohort_groups AS (
  SELECT *,
    CASE
      WHEN los_days <= 7 THEN 'short_stay'
      ELSE 'long_stay'
    END AS los_group
  FROM cohort
),
group_aggregates AS (
  SELECT
    los_group,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    AVG(hospital_expire_flag) * 100 AS mortality_rate_percent,
    APPROX_QUANTILES(
      IF(hospital_expire_flag = 1, DATETIME_DIFF(deathtime, admittime, DAY), NULL),
      2
    )[OFFSET(1)] AS median_time_to_death_days
  FROM cohort_groups
  GROUP BY los_group
)
SELECT
  MAX(IF(los_group = 'short_stay', mortality_rate_percent, NULL)) AS mortality_short_stay,
  MAX(IF(los_group = 'long_stay', mortality_rate_percent, NULL)) AS mortality_long_stay,
  MAX(IF(los_group = 'long_stay', mortality_rate_percent, NULL)) - 
  MAX(IF(los_group = 'short_stay', mortality_rate_percent, NULL)) AS absolute_difference,
  SAFE_DIVIDE(
    MAX(IF(los_group = 'long_stay', mortality_rate_percent, NULL)) - 
    MAX(IF(los_group = 'short_stay', mortality_rate_percent, NULL)),
    MAX(IF(los_group = 'short_stay', mortality_rate_percent, NULL))
  ) * 100 AS relative_difference_percent,
  MAX(IF(los_group = 'short_stay', median_time_to_death_days, NULL)) AS median_ttd_short_stay_days,
  MAX(IF(los_group = 'long_stay', median_time_to_death_days, NULL)) AS median_ttd_long_stay_days
FROM group_aggregates;