WITH
-- All ICU stays joined to patient demographics and hospital mortality
icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON icu.hadm_id = a.hadm_id
),

-- Identify heart failure admissions
hf_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%heart failure%'
),

-- HF ICU cohort
hf_icu AS (
  SELECT
    icu.*
  FROM
    icu
    JOIN hf_admissions hf
      ON icu.subject_id = hf.subject_id
      AND icu.hadm_id = hf.hadm_id
  WHERE
    icu.gender = 'M'
    AND icu.anchor_age BETWEEN 70 AND 80
),

-- Count lab events in first 72h for HF cohort
hf_lab_counts AS (
  SELECT
    h.stay_id,
    COUNT(le.labevent_id) AS lab_count
  FROM
    hf_icu h
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON h.subject_id = le.subject_id
      AND h.hadm_id = le.hadm_id
      AND le.charttime BETWEEN h.intime
        AND TIMESTAMP_ADD(h.intime, INTERVAL 72 HOUR)
  GROUP BY
    h.stay_id
),

-- HF diagnostic intensity statistics
hf_stats AS (
  SELECT
    'HF cohort (M, 70–80, heart failure)' AS cohort,
    AVG(lab_count) AS mean_lab_events_72h,
    APPROX_QUANTILES(lab_count, 100)[OFFSET(50)] AS median_lab_events_72h,
    APPROX_QUANTILES(lab_count, 100)[OFFSET(75)] AS p75_lab_events_72h,
    APPROX_QUANTILES(lab_count, 100)[OFFSET(95)] AS p95_lab_events_72h,
    NULL                        AS mean_icu_los,
    NULL                        AS hospital_mortality_rate
  FROM
    hf_lab_counts
),

-- General ICU population statistics
general_stats AS (
  SELECT
    'General ICU population' AS cohort,
    NULL                        AS mean_lab_events_72h,
    NULL                        AS median_lab_events_72h,
    NULL                        AS p75_lab_events_72h,
    NULL                        AS p95_lab_events_72h,
    AVG(icu.los)                AS mean_icu_los,
    AVG(icu.hospital_expire_flag) AS hospital_mortality_rate
  FROM
    icu
)

-- Combine both results
SELECT * FROM hf_stats
UNION ALL
SELECT * FROM general_stats;