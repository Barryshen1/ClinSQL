WITH
-- Admissions of interest: female, age 44-54, LOS 1-7 days, and with a TIA diagnosis
tia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%transient ischemic attack%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    -- Ensure LOS is computable and between 1 and 7 days inclusive
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
-- HCPCS-based imaging events filtered by imaging keywords in the hcpcs description
hcpcs_imaging AS (
  SELECT
    he.hadm_id,
    he.hcpcs_cd AS code,
    he.chartdate AS evt_date,
    dh.long_description
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
      ON he.hcpcs_cd = dh.code
  WHERE
    -- look for common imaging/radiology keywords in the HCPCS description
    dh.long_description IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(dh.long_description),
      r'(ct|computed tomography|computed tomograph|magnetic resonance|mri|x[- ]?ray|radiograph|ultrasound|sonography)')
),
-- ICD procedure-based imaging events filtered by keywords in procedure titles
icdproc_imaging AS (
  SELECT
    p.hadm_id,
    p.icd_code AS code,
    p.chartdate AS evt_date,
    dp.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON p.icd_code = dp.icd_code
      AND p.icd_version = dp.icd_version
  WHERE
    dp.long_title IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(dp.long_title),
      r'(ct|computed tomography|computed tomograph|magnetic resonance|mri|x[- ]?ray|radiograph|ultrasound|sonography)')
),
-- Union of imaging events (deduplicated later by hadm_id + code + date)
imaging_events_union AS (
  SELECT hadm_id, code, evt_date FROM hcpcs_imaging
  UNION ALL
  SELECT hadm_id, code, evt_date FROM icdproc_imaging
),
-- Count imaging events per admission (deduplicate by hadm_id + code + evt_date)
imaging_count_per_adm AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT CONCAT(COALESCE(code, ''), '|' , CAST(COALESCE(evt_date, DATE '1900-01-01') AS STRING))) AS imaging_count
  FROM
    imaging_events_union
  GROUP BY hadm_id
),
-- Flag ICU use per admission
icu_flag AS (
  SELECT DISTINCT hadm_id, TRUE AS icu_used
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
-- Combine admissions, imaging counts and ICU flag, compute LOS bucket
admissions_with_counts AS (
  SELECT
    ta.hadm_id,
    ta.subject_id,
    ta.los_days,
    CASE
      WHEN ta.los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN ta.los_days BETWEEN 5 AND 7 THEN '5-7'
      ELSE 'other'
    END AS los_bucket,
    IF(ic.icu_used IS TRUE, 'Yes', 'No') AS icu_use,
    COALESCE(icnt.imaging_count, 0) AS imaging_count
  FROM
    tia_admissions ta
    LEFT JOIN imaging_count_per_adm icnt
      USING(hadm_id)
    LEFT JOIN icu_flag ic
      USING(hadm_id)
  WHERE
    ta.los_days BETWEEN 1 AND 7  -- already ensured but keep explicit
    AND (ta.los_days BETWEEN 1 AND 4 OR ta.los_days BETWEEN 5 AND 7)
)
-- Final aggregation: for each LOS bucket and ICU use, compute counts and p25/p50/p75
SELECT
  los_bucket,
  icu_use,
  COUNT(*) AS n_admissions,
  -- Use APPROX_QUANTILES with 100 buckets; 25th percentile index = 24, median = 49, 75th = 74
  ARRAY_AGG(qs)[ORDINAL(1)].p25 AS p25_imaging_per_adm,
  ARRAY_AGG(qs)[ORDINAL(1)].p50 AS p50_imaging_per_adm,
  ARRAY_AGG(qs)[ORDINAL(1)].p75 AS p75_imaging_per_adm
FROM (
  SELECT
    los_bucket,
    icu_use,
    -- compute quantile array for this subgroup
    STRUCT(
      APPROX_QUANTILES(imaging_count, 100)[OFFSET(24)] AS p25,
      APPROX_QUANTILES(imaging_count, 100)[OFFSET(49)] AS p50,
      APPROX_QUANTILES(imaging_count, 100)[OFFSET(74)] AS p75
    ) AS qs
  FROM
    admissions_with_counts
  GROUP BY los_bucket, icu_use
)
GROUP BY los_bucket, icu_use
ORDER BY
  los_bucket,
  icu_use;