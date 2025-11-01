WITH age_calc AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 59 AND 69
),

hf_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%heart failure%'
    OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
    OR (di.icd_version = 9 AND di.icd_code LIKE '428%')
),

aki_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
    OR (di.icd_version = 9 AND di.icd_code = '584')
),

ards_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    (di.icd_version = 10 AND di.icd_code = 'J80')
    OR (di.icd_version = 9 AND di.icd_code = '518.82')
),

cohort AS (
  SELECT
    ac.*
  FROM
    age_calc ac
  INNER JOIN
    hf_diagnoses hf
  ON
    ac.hadm_id = hf.hadm_id
),

outcomes AS (
  SELECT
    c.hadm_id,
    c.age_at_admission,
    c.hospital_expire_flag,
    COALESCE(aki.hadm_id IS NOT NULL, FALSE) AS has_aki,
    COALESCE(ards.hadm_id IS NOT NULL, FALSE) AS has_ards,
    CASE
      WHEN c.hospital_expire_flag = 1 THEN DATETIME_DIFF(c.deathtime, c.admittime, HOUR) / 24.0
      ELSE NULL
    END AS survival_days
  FROM
    cohort c
  LEFT JOIN
    aki_diagnoses aki
  ON
    c.hadm_id = aki.hadm_id
  LEFT JOIN
    ards_diagnoses ards
  ON
    c.hadm_id = ards.hadm_id
)

SELECT
  -- In-hospital mortality rate
  AVG(hospital_expire_flag) AS mortality_rate,
  -- AKI rate
  AVG(CAST(has_aki AS INT64)) AS aki_rate,
  -- ARDS rate
  AVG(CAST(has_ards AS INT64)) AS ards_rate,
  -- Median survival among in-hospital deaths (in days)
  APPROX_QUANTILES(survival_days, 100)[OFFSET(50)] AS median_survival_days_in_deaths,
  -- Composite risk score distribution (using age as proxy)
  MIN(age_at_admission) AS age_min,
  APPROX_QUANTILES(age_at_admission, 100)[OFFSET(25)] AS age_p25,
  APPROX_QUANTILES(age_at_admission, 100)[OFFSET(50)] AS age_median,
  APPROX_QUANTILES(age_at_admission, 100)[OFFSET(75)] AS age_p75,
  APPROX_QUANTILES(age_at_admission, 100)[OFFSET(90)] AS age_p90,
  MAX(age_at_admission) AS age_max
FROM
  outcomes;