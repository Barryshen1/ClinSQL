WITH cohort AS (
  -- All female ICU stays age 53-63
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 53 AND 63
),

sepsis_hadm AS (
  -- hadm_id with sepsis diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    (
      -- ICD-10 sepsis
      (d.icd_version = 10 AND (LEFT(d.icd_code, 3) = 'A40' OR LEFT(d.icd_code, 3) = 'A41'))
      -- ICD-9 sepsis
      OR (d.icd_version = 9 AND d.icd_code IN ('99591', '99592', '78552'))
    )
),

procedures_24h AS (
  -- Count procedures in first 24h of ICU stay
  SELECT
    c.stay_id,
    COUNT(p.icd_code) AS proc_count
  FROM
    cohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON c.subject_id = p.subject_id
    AND c.hadm_id = p.hadm_id
    AND p.chartdate >= c.intime
    AND p.chartdate < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY
    c.stay_id
),

outcomes AS (
  -- Add LOS and hospital mortality
  SELECT
    c.stay_id,
    c.hadm_id,
    c.los,
    COALESCE(proc.proc_count, 0) AS proc_count,
    a.hospital_expire_flag,
    CASE WHEN c.hadm_id IN (SELECT hadm_id FROM sepsis_hadm) THEN 'sepsis' ELSE 'non_sepsis' END AS cohort_type
  FROM
    cohort c
  LEFT JOIN
    procedures_24h proc
    ON c.stay_id = proc.stay_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.hadm_id = a.hadm_id
)

SELECT
  cohort_type,
  APPROX_QUANTILES(proc_count, 100)[75] AS proc_count_75th_percentile,
  APPROX_QUANTILES(proc_count, 100)[90] AS proc_count_90th_percentile,
  AVG(los) AS avg_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
FROM
  outcomes
GROUP BY
  cohort_type
ORDER BY
  cohort_type;