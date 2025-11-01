WITH base AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
ami_filtered AS (
  SELECT
    b.hadm_id,
    b.subject_id,
    a.admittime,
    b.dischtime,
    b.deathtime,
    b.admission_type,
    b.hospital_expire_flag,
    (b.anchor_age + (EXTRACT(YEAR FROM a.admittime) - b.anchor_year)) AS age_at_adm
  FROM base AS b
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = b.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = b.subject_id AND di.hadm_id = b.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE (
          (di.icd_version = 9 AND di.icd_code LIKE '410%')
          OR
          (di.icd_version = 10 AND di.icd_code LIKE 'I21%')
        )
    AND LOWER(dd.long_title) LIKE '%myocardial infarction%'
    -- Age at admission within 66-76
    AND (b.anchor_age + (EXTRACT(YEAR FROM a.admittime) - b.anchor_year)) BETWEEN 66 AND 76
),
metrics AS (
  SELECT
    m.hadm_id,
    m.subject_id,
    m.admittime,
    m.dischtime,
    m.deathtime,
    m.admission_type,
    m.hospital_expire_flag,
    m.age_at_adm,
    CASE
      -- LOS in days: use dischtime if available; else use deathtime if patient died
      WHEN m.dischtime IS NOT NULL THEN DATE_DIFF(DATE(m.dischtime), DATE(m.admittime), DAY)
      WHEN m.deathtime IS NOT NULL THEN DATE_DIFF(DATE(m.deathtime), DATE(m.admittime), DAY)
      ELSE NULL
    END AS los_days,
    CASE
      -- Time to death in days (only for those who died)
      WHEN m.deathtime IS NOT NULL THEN DATE_DIFF(DATE(m.deathtime), DATE(m.admittime), DAY)
      ELSE NULL
    END AS time_to_death_days,
    CASE WHEN (m.deathtime IS NOT NULL OR m.hospital_expire_flag = 1) THEN 1 ELSE 0 END AS died_in_hosp
  FROM ami_filtered AS m
),
labeled AS (
  SELECT
    CASE
      WHEN los_days IS NULL THEN 'Unknown'
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN los_days >= 8 THEN '>=8'
    END AS los_bucket,
    CASE WHEN LOWER(admission_type) = 'emergency' THEN 'Emergent' ELSE 'Non-Emergent' END AS admission_status,
    los_days,
    time_to_death_days,
    died_in_hosp
  FROM metrics
  WHERE los_days IS NOT NULL
),
counts AS (
  -- summary counts per group
  SELECT
    los_bucket,
    admission_status,
    COUNT(*) AS total_admissions,
    SUM(died_in_hosp) AS in_hospital_deaths
  FROM labeled
  GROUP BY los_bucket, admission_status
),
medians AS (
  -- median time-to-death per group (among those with time_to_death_days)
  SELECT
    l.los_bucket,
    l.admission_status,
    APPROX_QUANTILES(l.time_to_death_days, 100)[OFFSET(50)] AS median_time_to_death_days
  FROM labeled AS l
  WHERE l.time_to_death_days IS NOT NULL
  GROUP BY l.los_bucket, l.admission_status
)
SELECT
  c.los_bucket AS los_bucket,
  c.admission_status AS admission_status,
  c.total_admissions,
  c.in_hospital_deaths,
  SAFE_DIVIDE(c.in_hospital_deaths, c.total_admissions) * 100 AS mortality_percent,
  m.median_time_to_death_days
FROM counts AS c
LEFT JOIN medians AS m
  ON c.los_bucket = m.los_bucket
  AND c.admission_status = m.admission_status
ORDER BY los_bucket, admission_status;