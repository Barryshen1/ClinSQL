WITH patient_ages AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
),
ami_patients AS (
  SELECT DISTINCT
    pa.subject_id
  FROM
    patient_ages pa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  ON
    pa.subject_id = di.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%myocardial infarction%'
    AND (
      LOWER(d.long_title) LIKE '%acute%'
      OR LOWER(d.long_title) LIKE '%st elevation%'
      OR LOWER(d.long_title) LIKE '%nonst elevation%'
    )
),
icu_patients AS (
  SELECT DISTINCT
    i.subject_id
  FROM
    `physionet-data.mimiciv_3_1_icu`.icustays i
),
cohort AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    p.dod
  FROM
    patient_ages pa
  INNER JOIN
    ami_patients am
  ON
    pa.subject_id = am.subject_id
  INNER JOIN
    icu_patients icu
  ON
    pa.subject_id = icu.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients p
  ON
    pa.subject_id = p.subject_id
  WHERE
    pa.age_at_admission >= 88
    AND pa.age_at_admission <= 98
),
outcomes AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dod,
    -- 30-day mortality
    CASE
      WHEN dod IS NOT NULL AND dod <= DATETIME_ADD(admittime, INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS died_within_30d,
    -- Survival time in days if died within 30d
    CASE
      WHEN dod IS NOT NULL AND dod <= DATETIME_ADD(admittime, INTERVAL 30 DAY)
      THEN DATETIME_DIFF(dod, admittime, HOUR) / 24.0
      ELSE NULL
    END AS survival_days
  FROM
    cohort
)
SELECT
  COUNT(*) AS cohort_size,
  AVG(died_within_30d) AS mortality_rate_30d,
  APPROX_QUANTILES(survival_days, 100)[OFFSET(50)] AS median_survival_days_decedents
FROM
  outcomes;