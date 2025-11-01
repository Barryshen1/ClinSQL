WITH
-- 1) ACS diagnosis codes (keyword-based)
acs_diag_codes AS (
  SELECT icd_code, icd_version, long_title
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    LOWER(long_title) LIKE '%myocardial%'            -- myocardial infarction / myocardial
    OR LOWER(long_title) LIKE '%acute coronary%'     -- acute coronary
    OR LOWER(long_title) LIKE '%unstable angina%'    -- unstable angina
    OR LOWER(long_title) LIKE '%stemi%'              -- STEMI
    OR LOWER(long_title) LIKE '%acute myocardial%'   -- explicit phrase
    OR LOWER(long_title) LIKE '%coronary%'           -- coronary
    OR LOWER(long_title) LIKE '%acute mi%'           -- some abbreviations
  )
),

-- 2) Diagnoses filtered to ACS
acs_diagnoses AS (
  SELECT d.subject_id, d.hadm_id, d.seq_num, d.icd_code, dd.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN acs_diag_codes dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
),

-- 3) Admissions meeting demographic, LOS and ACS criteria
cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS los_group,
    -- primary ACS if any ACS diagnosis for this hadm_id has seq_num = 1
    MAX(CASE WHEN ad.seq_num = 1 THEN 1 ELSE 0 END) AS primary_acs_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN acs_diagnoses ad
    ON a.hadm_id = ad.hadm_id
  -- require male and age 39-49 inclusive
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    -- LOS filter will be applied afterwards when checking los_group not null
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime
),

-- 4) Keep only admissions that have ACS (primary or secondary) and LOS between 1 and 7
cohort_with_acs AS (
  SELECT c.*
  FROM cohort_admissions c
  JOIN (
    -- admissions that have any ACS diagnosis (primary or secondary)
    SELECT DISTINCT hadm_id
    FROM acs_diagnoses
  ) ad
  ON c.hadm_id = ad.hadm_id
  WHERE c.los_group IS NOT NULL
),

-- 5) Ultrasound events from hcpcsevents (billing) with keyword filter, restricted to cohort admission dates
hcpcs_ultrasound_events AS (
  SELECT
    h.hadm_id,
    h.chartdate AS event_date,
    h.hcpcs_cd AS code,
    'hcpcs' AS source
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  JOIN cohort_with_acs c
    ON h.hadm_id = c.hadm_id
    -- ensure event occurred during admission
    AND h.chartdate BETWEEN DATE(c.admittime) AND DATE(c.dischtime)
  WHERE (
    LOWER(COALESCE(h.short_description, '')) LIKE '%ultrasound%'
    OR LOWER(COALESCE(h.short_description, '')) LIKE '%echo%'
    OR LOWER(COALESCE(h.short_description, '')) LIKE '%echocardi%'
    OR LOWER(COALESCE(d.long_description, '')) LIKE '%ultrasound%'
    OR LOWER(COALESCE(d.long_description, '')) LIKE '%echo%'
    OR LOWER(COALESCE(d.long_description, '')) LIKE '%echocardi%'
    OR LOWER(COALESCE(d.long_description, '')) LIKE '%sonogram%'
  )
),

-- 6) Ultrasound events from procedures_icd (ICD procedure titles)
icdproc_ultrasound_events AS (
  SELECT
    p.hadm_id,
    p.chartdate AS event_date,
    p.icd_code AS code,
    'icd_proc' AS source
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON p.icd_code = dp.icd_code
    AND p.icd_version = dp.icd_version
  JOIN cohort_with_acs c
    ON p.hadm_id = c.hadm_id
    AND p.chartdate BETWEEN DATE(c.admittime) AND DATE(c.dischtime)
  WHERE (
    LOWER(COALESCE(dp.long_title, '')) LIKE '%ultrasound%'
    OR LOWER(COALESCE(dp.long_title, '')) LIKE '%echo%'
    OR LOWER(COALESCE(dp.long_title, '')) LIKE '%echocardi%'
    OR LOWER(COALESCE(dp.long_title, '')) LIKE '%sonogram%'
  )
),

-- 7) Union and deduplicate event-level rows per admission
us_events_union AS (
  SELECT DISTINCT hadm_id, event_date, code, source
  FROM (
    SELECT * FROM hcpcs_ultrasound_events
    UNION ALL
    SELECT * FROM icdproc_ultrasound_events
  )
),

-- 8) Count ultrasounds per admission (only for admissions in cohort)
us_counts AS (
  SELECT
    c.hadm_id,
    COUNT(1) AS us_count
  FROM cohort_with_acs c
  LEFT JOIN us_events_union u
    ON c.hadm_id = u.hadm_id
  GROUP BY c.hadm_id
)

-- Final aggregation: percentiles by LOS group (1-4 vs 5-7) and primary vs secondary ACS
SELECT
  c.los_group AS los_group,
  CASE WHEN c.primary_acs_flag = 1 THEN 'primary' ELSE 'secondary' END AS acs_type,
  (APPROX_QUANTILES(u.us_count, 100))[OFFSET(25)] AS p25_ultrasounds,
  (APPROX_QUANTILES(u.us_count, 100))[OFFSET(50)] AS p50_ultrasounds,
  (APPROX_QUANTILES(u.us_count, 100))[OFFSET(75)] AS p75_ultrasounds,
  COUNT(1) AS n_admissions
FROM (
  SELECT
    c.hadm_id,
    c.los_group,
    c.primary_acs_flag,
    COALESCE(uc.us_count, 0) AS us_count
  FROM cohort_with_acs c
  LEFT JOIN us_counts uc
    ON c.hadm_id = uc.hadm_id
) u
JOIN cohort_with_acs c
  ON u.hadm_id = c.hadm_id
GROUP BY c.los_group, c.primary_acs_flag
ORDER BY c.los_group, acs_type;