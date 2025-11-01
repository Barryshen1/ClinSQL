WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.deathtime,
    a.hospital_expire_flag,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 53 AND 63
),

icu_stays_with_los AS (
  SELECT
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los AS icu_los_days,
    CASE WHEN i.los <= 7 THEN '≤7' ELSE '>7' END AS los_group
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
),

-- Diagnoses: identify sepsis and septic shock
diagnosis_groups AS (
  SELECT
    di.hadm_id,
    MAX(CASE WHEN di.icd_code = 'R6521' AND di.icd_version = 10 THEN 1 ELSE 0 END) AS has_septic_shock,
    MAX(CASE WHEN di.icd_code IN ('A419', 'A418', 'A4151', 'A4159') AND di.icd_version = 10 THEN 1 ELSE 0 END) AS has_sepsis
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  GROUP BY di.hadm_id
),

-- Assign group: prioritize septic shock over sepsis
cohort AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.age_at_admit,
    pa.admittime,
    pa.deathtime,
    pa.hospital_expire_flag,
    ics.stay_id,
    ics.intime,
    ics.outtime,
    ics.icu_los_days,
    ics.los_group,
    CASE
      WHEN dg.has_septic_shock = 1 THEN 'Septic Shock'
      WHEN dg.has_sepsis = 1 THEN 'Sepsis'
      ELSE NULL
    END AS sepsis_group
  FROM patient_admissions pa
  INNER JOIN icu_stays_with_los ics ON pa.hadm_id = ics.hadm_id
  INNER JOIN diagnosis_groups dg ON pa.hadm_id = dg.hadm_id
  WHERE dg.has_septic_shock = 1 OR dg.has_sepsis = 1
),

-- For time-to-death in non-survivors
time_to_death AS (
  SELECT
    subject_id,
    hadm_id,
    sepsis_group,
    los_group,
    hospital_expire_flag,
    CASE
      WHEN hospital_expire_flag = 1 AND deathtime IS NOT NULL AND intime IS NOT NULL
      THEN DATETIME_DIFF(deathtime, intime, HOUR)
      ELSE NULL
    END AS time_to_death_hours
  FROM cohort
)

-- Final aggregation
SELECT
  sepsis_group,
  los_group,
  COUNT(*) AS n,
  AVG(hospital_expire_flag) AS mortality_rate,
  APPROX_QUANTILES(time_to_death_hours, 100)[OFFSET(50)] AS median_time_to_death_hours
FROM time_to_death
GROUP BY sepsis_group, los_group
ORDER BY sepsis_group, los_group;