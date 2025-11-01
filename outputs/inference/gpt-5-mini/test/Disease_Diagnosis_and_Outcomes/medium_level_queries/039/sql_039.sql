WITH ami_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND STARTS_WITH(icd_code, '410'))
    OR
    (icd_version = 10 AND (STARTS_WITH(UPPER(icd_code), 'I21') OR STARTS_WITH(UPPER(icd_code), 'I22')))
  )
),

exclude_shock_resp AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    -- Shock:
    (icd_version = 9 AND STARTS_WITH(icd_code, '7855')) OR
    (icd_version = 10 AND STARTS_WITH(UPPER(icd_code), 'R57'))
  )
  OR (
    -- Respiratory failure:
    (icd_version = 9 AND (STARTS_WITH(icd_code, '5188') OR icd_code = '7991')) OR
    (icd_version = 10 AND STARTS_WITH(UPPER(icd_code), 'J96'))
  )
),

cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    p.gender,
    p.anchor_age,
    -- LOS in days (inclusive)
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
    AND a.hadm_id IN (SELECT hadm_id FROM ami_hadms)
    AND a.hadm_id NOT IN (SELECT hadm_id FROM exclude_shock_resp)
),

cohort_derived AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    admission_type,
    anchor_age,
    los_days,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_bucket,
    CASE
      WHEN LOWER(COALESCE(admission_type, '')) = 'emergency' THEN 'Emergency'
      ELSE 'Non-emergency'
    END AS admission_urgency,
    -- time-to-death in fractional days; NULL if not expired in-hospital
    CASE
      WHEN hospital_expire_flag = 1 AND deathtime IS NOT NULL THEN
        TIMESTAMP_DIFF(deathtime, admittime, SECOND) / 86400.0
      ELSE NULL
    END AS days_to_death
  FROM cohort
)

SELECT
  los_bucket,
  admission_urgency AS admission_type_group,
  COUNT(*) AS n_admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)), 2) AS mortality_pct,
  -- median time-to-death among those who died in-hospital in this group (NULL if no deaths)
  APPROX_QUANTILES(IF(hospital_expire_flag = 1, days_to_death, NULL), 100)[OFFSET(50)] AS median_time_to_death_days
FROM cohort_derived
GROUP BY los_bucket, admission_urgency
ORDER BY
  CASE los_bucket WHEN '1-3' THEN 1 WHEN '4-7' THEN 2 ELSE 3 END,
  CASE admission_urgency WHEN 'Emergency' THEN 1 ELSE 2 END;