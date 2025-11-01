WITH first_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
)
, cohort_base AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    p.gender,
    p.anchor_age
  FROM
    first_icu_stays f
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON f.subject_id = p.subject_id
  WHERE
    f.rn = 1
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
)
, sepsis_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10 sepsis: A40.*, A41.*
    (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%'))
    -- ICD-9 sepsis: 99591, 99592, 78552, 038.*
    OR (icd_version = 9 AND (
      icd_code IN ('99591', '99592', '78552')
      OR icd_code LIKE '038%'
    ))
)
, sepsis_patients AS (
  SELECT DISTINCT c.subject_id, c.hadm_id
  FROM cohort_base c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
    JOIN sepsis_codes s
      ON d.icd_code = s.icd_code AND d.icd_version = s.icd_version
)
, controls_patients AS (
  SELECT c.subject_id, c.hadm_id
  FROM cohort_base c
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN sepsis_codes s
        ON d.icd_code = s.icd_code AND d.icd_version = s.icd_version
    WHERE d.subject_id = c.subject_id AND d.hadm_id = c.hadm_id
  )
)
, procedures_48h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT p.icd_code) AS n_distinct_procedures
  FROM
    cohort_base c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
      ON c.subject_id = p.subject_id
      AND c.hadm_id = p.hadm_id
      AND p.chartdate >= c.intime
      AND p.chartdate < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.subject_id, c.hadm_id
)
, outcomes AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS hospital_los
  FROM
    cohort_base c
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON c.subject_id = a.subject_id AND c.hadm_id = a.hadm_id
)
-- Final aggregation
SELECT
  'Sepsis' AS cohort,
  APPROX_QUANTILES(p.n_distinct_procedures, 10)[9] AS procedures_90th_percentile,
  AVG(o.hospital_los) AS avg_hospital_los,
  APPROX_QUANTILES(o.hospital_los, 2)[1] AS median_hospital_los,
  AVG(o.hospital_expire_flag) AS mortality_rate
FROM
  sepsis_patients s
  JOIN procedures_48h p ON s.subject_id = p.subject_id AND s.hadm_id = p.hadm_id
  JOIN outcomes o ON s.subject_id = o.subject_id AND s.hadm_id = o.hadm_id

UNION ALL

SELECT
  'Control' AS cohort,
  NULL AS procedures_90th_percentile,
  AVG(o.hospital_los) AS avg_hospital_los,
  APPROX_QUANTILES(o.hospital_los, 2)[1] AS median_hospital_los,
  AVG(o.hospital_expire_flag) AS mortality_rate
FROM
  controls_patients c
  JOIN procedures_48h p ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  JOIN outcomes o ON c.subject_id = o.subject_id AND c.hadm_id = o.hadm_id;