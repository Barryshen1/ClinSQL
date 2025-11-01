WITH
-- 1) Select admissions for female patients aged 73-83 and ED/ELECTIVE admission types
female_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    -- inclusive calendar day count: same-day = 1
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) + 1 AS stay_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE')
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- 2) Candidate ultrasound / echocardiography events from hcpcsevents (with descriptions)
hcpcs_us AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.chartdate AS event_date,
    UPPER(d.short_description) AS description
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
  ON
    h.hcpcs_cd = d.code
  WHERE
    -- match common ultrasound/echo keywords in description
    REGEXP_CONTAINS(UPPER(d.short_description),
      r'ULTRASOUND|ULTRASON|SONOGRAPH|ECHO|ECHOCARD|TRANSTHORACIC|TRANSESOPH')
    AND h.hadm_id IS NOT NULL
),

-- 3) Candidate ultrasound / echocardiography events from procedures_icd (with long_title)
icdproc_us AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.chartdate AS event_date,
    UPPER(d.long_title) AS description
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    p.icd_code = d.icd_code
    -- compare icd_version in a type-safe way and treat both NULL as match
    AND (
      SAFE_CAST(p.icd_version AS STRING) = SAFE_CAST(d.icd_version AS STRING)
      OR (p.icd_version IS NULL AND d.icd_version IS NULL)
    )
  WHERE
    REGEXP_CONTAINS(UPPER(d.long_title),
      r'ULTRASOUND|ULTRASON|SONOGRAPH|ECHO|ECHOCARD|TRANSTHORACIC|TRANSESOPH')
    AND p.hadm_id IS NOT NULL
),

-- 4) Union the two sources of ultrasound events
all_us_events AS (
  SELECT * FROM hcpcs_us
  UNION ALL
  SELECT * FROM icdproc_us
),

-- 5) De-duplicate obvious duplicates per admission by date+description, then count per admission
us_count_per_adm AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT CONCAT(CAST(event_date AS STRING), '||', description)) AS us_count
  FROM
    all_us_events
  GROUP BY
    hadm_id
),

-- 6) Combine counts with admissions, restrict to stay bins of interest
admissions_with_counts AS (
  SELECT
    fa.hadm_id,
    fa.subject_id,
    fa.admission_type,
    fa.stay_days,
    COALESCE(u.us_count, 0) AS us_count,
    CASE
      WHEN fa.stay_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN fa.stay_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS stay_bin
  FROM
    female_admissions fa
  LEFT JOIN
    us_count_per_adm u
  USING (hadm_id)
  WHERE
    fa.stay_days BETWEEN 1 AND 7
    -- keep only the two bins
    AND (fa.stay_days BETWEEN 1 AND 3 OR fa.stay_days BETWEEN 4 AND 7)
)

-- 7) Final aggregation: mean, min, max ultrasounds per admission for each bin and admission_type
SELECT
  stay_bin,
  admission_type,
  -- mean as floating point
  ROUND(AVG(us_count), 3) AS mean_ultrasounds_per_admission,
  MIN(us_count) AS min_ultrasounds_per_admission,
  MAX(us_count) AS max_ultrasounds_per_admission,
  COUNT(*) AS admissions_in_group
FROM
  admissions_with_counts
GROUP BY
  stay_bin,
  admission_type
ORDER BY
  stay_bin,
  admission_type;