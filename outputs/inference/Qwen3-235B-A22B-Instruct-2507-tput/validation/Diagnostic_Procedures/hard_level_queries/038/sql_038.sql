WITH patients_age AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE
    gender = 'M'
),
icu_with_age AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    a.hospital_expire_flag,
    (EXTRACT(YEAR FROM ie.intime) - (pa.anchor_year - pa.anchor_age)) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_icu`.icustays ie
  JOIN
    patients_age pa
    ON ie.subject_id = pa.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON ie.hadm_id = a.hadm_id
),
-- First ICU stay per patient
first_icu_stay AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM
    icu_with_age
),
first_stays AS (
  SELECT * EXCEPT(rn)
  FROM first_icu_stay
  WHERE rn = 1
),
-- Intracranial hemorrhage: ICD-10 codes I60, I61, I62
icd_codes AS (
  SELECT
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE
    (LOWER(long_title) LIKE '%intracranial hemorrhage%'
     OR LOWER(long_title) LIKE '%intracerebral hemorrhage%'
     OR LOWER(long_title) LIKE '%subarachnoid hemorrhage%'
     OR SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
    AND icd_version = 10
),
target_cohort AS (
  SELECT
    fs.*
  FROM
    first_stays fs
  WHERE
    fs.age_at_admission >= 60
    AND fs.age_at_admission <= 70
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
      WHERE di.hadm_id = fs.hadm_id
        AND di.icd_version = 10
        AND di.icd_code IN (SELECT icd_code FROM icd_codes)
    )
),
general_cohort AS (
  SELECT * FROM first_stays
),
-- Procedure burden in first 72h
procedure_counts AS (
  SELECT
    pe.stay_id,
    COUNT(*) AS procedure_count
  FROM
    `physionet-data.mimiciv_3_1_icu`.procedureevents pe
  JOIN
    first_stays fs
    ON pe.stay_id = fs.stay_id
  WHERE
    pe.starttime >= fs.intime
    AND pe.starttime <= DATETIME_ADD(fs.intime, INTERVAL 72 HOUR)
  GROUP BY
    pe.stay_id
),
target_procedure_burden AS (
  SELECT
    APPROX_QUANTILES(COALESCE(pc.procedure_count, 0), 1000)[OFFSET(750)] AS procedure_burden_75th_percentile,
    AVG(fs.los) AS mean_icu_los_days,
    AVG(CAST(fs.hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
  FROM
    target_cohort fs
  LEFT JOIN
    procedure_counts pc
    ON fs.stay_id = pc.stay_id
),
general_procedure_burden AS (
  SELECT
    APPROX_QUANTILES(COALESCE(pc.procedure_count, 0), 1000)[OFFSET(750)] AS procedure_burden_75th_percentile,
    AVG(fs.los) AS mean_icu_los_days,
    AVG(CAST(fs.hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
  FROM
    general_cohort fs
  LEFT JOIN
    procedure_counts pc
    ON fs.stay_id = pc.stay_id
)
SELECT
  'target' AS cohort,
  procedure_burden_75th_percentile,
  mean_icu_los_days,
  hospital_mortality_rate
FROM
  target_procedure_burden
UNION ALL
SELECT
  'general' AS cohort,
  procedure_burden_75th_percentile,
  mean_icu_los_days,
  hospital_mortality_rate
FROM
  general_procedure_burden;