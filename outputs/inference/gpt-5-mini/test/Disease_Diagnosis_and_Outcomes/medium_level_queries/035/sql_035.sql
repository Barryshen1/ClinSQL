WITH
-- Pull diagnoses with ICD description text
diag_with_text AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    di.icd_code,
    di.icd_version,
    COALESCE(d.long_title, '') AS long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
),

-- For each hadm, determine whether there are upper- and/or lower-GI bleed diagnosis text matches
bleed_flags AS (
  SELECT
    hadm_id,
    MAX(CASE
      WHEN LOWER(long_title) LIKE '%esophag%' THEN 1
      WHEN LOWER(long_title) LIKE '%gastric%' THEN 1
      WHEN LOWER(long_title) LIKE '%duodenal%' THEN 1
      WHEN LOWER(long_title) LIKE '%mallory%' THEN 1
      WHEN LOWER(long_title) LIKE '%hematemesis%' THEN 1
      WHEN LOWER(long_title) LIKE '%melena%' THEN 1
      WHEN LOWER(long_title) LIKE '%peptic ulcer%' THEN 1
      WHEN LOWER(long_title) LIKE '%variceal%' THEN 1
      WHEN LOWER(long_title) LIKE '%upper%' THEN 1
      ELSE 0
    END) AS has_upper,
    MAX(CASE
      WHEN LOWER(long_title) LIKE '%colon%' THEN 1
      WHEN LOWER(long_title) LIKE '%colonic%' THEN 1
      WHEN LOWER(long_title) LIKE '%rectal%' THEN 1
      WHEN LOWER(long_title) LIKE '%rectum%' THEN 1
      WHEN LOWER(long_title) LIKE '%diverticul%' THEN 1
      WHEN LOWER(long_title) LIKE '%hematochezia%' THEN 1
      WHEN LOWER(long_title) LIKE '%sigmoid%' THEN 1
      WHEN LOWER(long_title) LIKE '%anal%' THEN 1
      WHEN LOWER(long_title) LIKE '%lower%' THEN 1
      ELSE 0
    END) AS has_lower
  FROM
    diag_with_text
  WHERE
    -- Focus on diagnoses that mention bleeding/hemorrhage or GI terms (helps reduce irrelevant matches)
    (
      LOWER(long_title) LIKE '%hemorrh%' OR
      LOWER(long_title) LIKE '%bleed%' OR
      LOWER(long_title) LIKE '%gastrointestinal%' OR
      LOWER(long_title) LIKE '%melena%' OR
      LOWER(long_title) LIKE '%hematemesis%' OR
      LOWER(long_title) LIKE '%hematochezia%' OR
      LOWER(long_title) LIKE '%peptic%'
    )
  GROUP BY
    hadm_id
),

-- Keep only hadm where we can classify as upper OR lower but not both (exclude ambiguous/unspecified)
bleed_cohort AS (
  SELECT
    hadm_id,
    CASE
      WHEN has_upper = 1 AND has_lower = 0 THEN 'upper'
      WHEN has_lower = 1 AND has_upper = 0 THEN 'lower'
      ELSE NULL
    END AS bleed_type
  FROM
    bleed_flags
  WHERE
    (has_upper = 1 AND has_lower = 0)
    OR (has_lower = 1 AND has_upper = 0)
),

-- ICU summary per hadm: earliest ICU intime and count of icu stays
icu_summary AS (
  SELECT
    hadm_id,
    MIN(intime) AS first_icu_intime,
    COUNT(*) AS icu_count
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY
    hadm_id
),

-- Main cohort: admissions joined to patients and bleed classification
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    b.bleed_type,
    -- hospital LOS in days (inclusive)
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS hosp_los_days,
    -- LOS bucket
    CASE
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 1 AND 2 THEN '1-2'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 3 AND 5 THEN '3-5'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 6 AND 9 THEN '6-9'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 >= 10 THEN '>=10'
      ELSE NULL
    END AS los_bucket,
    -- ICU flags: day1_icu if first ICU intime occurs within 24 hours of admission (on or after admittime, <= admittime + 1 day)
    CASE
      WHEN icu.first_icu_intime IS NOT NULL
           AND icu.first_icu_intime >= a.admittime
           AND icu.first_icu_intime <= TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
      THEN 'Yes' ELSE 'No' END AS day1_icu,
    CASE WHEN icu.icu_count IS NOT NULL AND icu.icu_count > 0 THEN 1 ELSE 0 END AS icu_any
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    bleed_cohort b
  ON
    a.hadm_id = b.hadm_id
  LEFT JOIN
    icu_summary icu
  ON
    a.hadm_id = icu.hadm_id
  WHERE
    -- female and age 69-79 inclusive
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    -- require valid discharge time and LOS at least 1 day
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 >= 1
),

-- Aggregate results by bleed type, LOS bucket, and day1 ICU status
agg AS (
  SELECT
    bleed_type,
    los_bucket,
    day1_icu,
    COUNT(1) AS n_admissions,
    SUM(COALESCE(hospital_expire_flag, 0)) AS deaths,
    SAFE_DIVIDE(SUM(COALESCE(hospital_expire_flag, 0)) , COUNT(1)) * 100.0 AS mortality_pct,
    SUM(icu_any) AS icu_admit_count,
    SAFE_DIVIDE(SUM(icu_any), COUNT(1)) * 100.0 AS icu_admit_rate_pct
  FROM
    cohort
  GROUP BY
    bleed_type, los_bucket, day1_icu
)

SELECT
  bleed_type,
  los_bucket,
  day1_icu,
  n_admissions,
  deaths,
  ROUND(mortality_pct, 2) AS mortality_pct,
  icu_admit_count,
  ROUND(icu_admit_rate_pct, 2) AS icu_admit_rate_pct
FROM
  agg
ORDER BY
  bleed_type,
  los_bucket,
  day1_icu;