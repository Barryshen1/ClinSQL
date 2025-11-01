WITH
-- 1. Identify male ICU patients aged 88–98
base_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 88 AND 98
),

-- 2. Identify COPD exacerbation stays
copd_diag AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (
      -- ICD-10
      (icd_version = 10 AND (
        icd_code LIKE 'J44.1%' OR
        icd_code LIKE 'J44.0%' OR
        icd_code LIKE 'J44.9%'
      ))
      OR
      -- ICD-9
      (icd_version = 9 AND (
        icd_code = '49121' OR
        icd_code = '49122' OR
        icd_code = '496'
      ))
    )
),

copd_icu AS (
  SELECT
    b.*,
    1 AS is_copd
  FROM
    base_icu b
    JOIN copd_diag c
      ON b.subject_id = c.subject_id AND b.hadm_id = c.hadm_id
),

noncopd_icu AS (
  SELECT
    b.*,
    0 AS is_copd
  FROM
    base_icu b
    LEFT JOIN copd_diag c
      ON b.subject_id = c.subject_id AND b.hadm_id = c.hadm_id
  WHERE
    c.subject_id IS NULL
),

all_icu AS (
  SELECT * FROM copd_icu
  UNION ALL
  SELECT * FROM noncopd_icu
),

-- 3. Count distinct procedures in first 72h for each ICU stay
procedures_in_72h AS (
  SELECT
    icu.stay_id,
    COUNT(DISTINCT proc.icd_code) AS n_distinct_procs
  FROM
    copd_icu icu
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
      ON icu.subject_id = proc.subject_id
      AND icu.hadm_id = proc.hadm_id
      AND proc.chartdate IS NOT NULL
      AND proc.chartdate >= icu.intime
      AND proc.chartdate < DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
  GROUP BY
    icu.stay_id
),

-- 4. Get ICU LOS and hospital mortality for all ICU stays
icu_outcomes AS (
  SELECT
    icu.stay_id,
    icu.is_copd,
    icu.los,
    adm.hospital_expire_flag
  FROM
    all_icu icu
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.hadm_id = adm.hadm_id
),

-- 5. Aggregate results
copd_stats AS (
  SELECT
    'COPD' AS cohort,
    APPROX_QUANTILES(IFNULL(p.n_distinct_procs, 0), 4)[3] AS procedures_75th_percentile,
    AVG(o.los) AS mean_icu_los,
    AVG(CAST(o.hospital_expire_flag AS FLOAT64)) AS in_hosp_mortality_rate
  FROM
    copd_icu icu
    LEFT JOIN procedures_in_72h p
      ON icu.stay_id = p.stay_id
    LEFT JOIN icu_outcomes o
      ON icu.stay_id = o.stay_id
),

noncopd_stats AS (
  SELECT
    'Non-COPD' AS cohort,
    NULL AS procedures_75th_percentile,
    AVG(o.los) AS mean_icu_los,
    AVG(CAST(o.hospital_expire_flag AS FLOAT64)) AS in_hosp_mortality_rate
  FROM
    noncopd_icu icu
    LEFT JOIN icu_outcomes o
      ON icu.stay_id = o.stay_id
)

SELECT * FROM copd_stats
UNION ALL
SELECT * FROM noncopd_stats
ORDER BY cohort DESC;