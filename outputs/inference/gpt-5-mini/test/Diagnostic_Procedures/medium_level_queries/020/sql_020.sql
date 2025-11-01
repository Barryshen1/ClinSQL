WITH
-- Admissions of interest: female, age 72-82, with non-null admittime/dischtime
admissions_female AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 72 AND 82
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Admissions with a TIA diagnosis (ICD-9 435* or ICD-10 G45*)
tia_admissions AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    (d.icd_version = 9 AND d.icd_code LIKE '435%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'G45%')
),

-- ICU usage flag per admission
icu_flags AS (
  SELECT DISTINCT
    hadm_id,
    TRUE AS icu_used
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Imaging events from procedures_icd when the procedure description looks like imaging
imaging_from_procedures_icd AS (
  SELECT
    p.hadm_id,
    CONCAT('procicd_', COALESCE(p.icd_code, ''), '_', CAST(p.chartdate AS STRING)) AS evt_id,
    p.chartdate AS evt_date
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
      ON p.icd_code = d.icd_code
      AND p.icd_version = d.icd_version
  WHERE
    p.chartdate IS NOT NULL
    AND (
      d.long_title IS NOT NULL
      AND REGEXP_CONTAINS(LOWER(d.long_title), r'(ct|mri|x-?ray|radiograph|ultrasound|angio|fluoro|radiology|pet|spect)')
    )
),

-- Imaging events from hcpcsevents when the description looks like imaging
imaging_from_hcpcs AS (
  SELECT
    h.hadm_id,
    CONCAT('hcpcs_', COALESCE(h.hcpcs_cd, ''), '_', CAST(h.chartdate AS STRING)) AS evt_id,
    h.chartdate AS evt_date
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  WHERE
    h.chartdate IS NOT NULL
    AND (
      h.short_description IS NOT NULL
      AND REGEXP_CONTAINS(LOWER(h.short_description), r'(ct|mri|x-?ray|radiograph|ultrasound|angio|fluoro|radiology|pet|spect)')
    )
),

-- Union imaging events, then restrict to events occurring within the admission dates
imaging_events_all AS (
  SELECT * FROM imaging_from_procedures_icd
  UNION ALL
  SELECT * FROM imaging_from_hcpcs
),

-- Count distinct imaging events per admission, limited to admission date range
imaging_counts_per_adm AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT ie.evt_id) AS imaging_count
  FROM
    admissions_female a
    JOIN tia_admissions t ON a.hadm_id = t.hadm_id
    LEFT JOIN imaging_events_all ie
      ON ie.hadm_id = a.hadm_id
      -- ensure event date is within admission (inclusive)
      AND ie.evt_date BETWEEN DATE(a.admittime) AND DATE(a.dischtime)
  GROUP BY
    a.hadm_id
)

-- Final aggregation: group by LOS category and ICU use
SELECT
  los_group,
  IF(icu_used IS TRUE, 'ICU', 'No ICU') AS icu_usage,
  COUNT(*) AS admission_count,
  ROUND(AVG(imaging_count), 2) AS mean_imaging_procedures_per_admission
FROM (
  SELECT
    a.hadm_id,
    -- create LOS group only for requested windows; exclude others
    CASE
      WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN a.los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_group,
    IF(icu.icu_used IS TRUE, TRUE, FALSE) AS icu_used,
    COALESCE(ic.imaging_count, 0) AS imaging_count
  FROM
    admissions_female a
    JOIN tia_admissions t ON a.hadm_id = t.hadm_id
    LEFT JOIN icu_flags icu ON a.hadm_id = icu.hadm_id
    LEFT JOIN imaging_counts_per_adm ic ON a.hadm_id = ic.hadm_id
)
WHERE
  los_group IS NOT NULL
GROUP BY
  los_group,
  icu_used
ORDER BY
  los_group,
  icu_usage;