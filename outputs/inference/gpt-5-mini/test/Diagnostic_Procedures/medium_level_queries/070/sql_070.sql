WITH hf_admissions AS (
  -- Admissions for males 59-69 with a heart failure diagnosis and LOS between 1 and 8 days
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 5 AND 8 THEN '5-8'
    END AS length_group,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.hadm_id = a.hadm_id
      ) THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_use
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 8
    AND EXISTS (
      -- Heart failure diagnosis identified by description text in d_icd_diagnoses
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON di.icd_code = dicd.icd_code
       AND di.icd_version = dicd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%heart failure%'
    )
),

imaging_events_raw AS (
  -- HCPCS / CPT billed events (hospital)
  SELECT
    hadm_id,
    CAST(chartdate AS DATE) AS chart_date,
    short_description AS description
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE short_description IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(short_description),
      r'(\bct\b|\bx-?ray\b|\bx ray\b|\bradiograph\w*\b|\bradiography\b|\btomograph\w*\b|\bcat scan\b|\bcomputed tomography\b)')

  UNION ALL

  -- ICD-coded procedures (hospital) with lookup descriptions
  SELECT
    p.hadm_id,
    CAST(p.chartdate AS DATE) AS chart_date,
    d.long_title AS description
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
   AND p.icd_version = d.icd_version
  WHERE d.long_title IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(d.long_title),
      r'(\bct\b|\bx-?ray\b|\bx ray\b|\bradiograph\w*\b|\bradiography\b|\btomograph\w*\b|\bcat scan\b|\bcomputed tomography\b)')

  UNION ALL

  -- ICU procedureevents (ICU) — cast value to STRING because it can be numeric
  SELECT
    hadm_id,
    CAST(starttime AS DATE) AS chart_date,
    CAST(value AS STRING) AS description
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE value IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(CAST(value AS STRING)),
      r'(\bct\b|\bx-?ray\b|\bx ray\b|\bradiograph\w*\b|\bradiography\b|\btomograph\w*\b|\bcat scan\b|\bcomputed tomography\b)')
),

imaging_events_distinct AS (
  -- Deduplicate by hadm_id, date, and description to reduce double-counting
  SELECT DISTINCT
    hadm_id,
    chart_date,
    description
  FROM imaging_events_raw
),

imaging_counts AS (
  -- Count imaging events per admission
  SELECT
    hadm_id,
    COUNT(1) AS imaging_count
  FROM imaging_events_distinct
  GROUP BY hadm_id
),

admissions_with_counts AS (
  -- Left join to ensure admissions with zero imaging are included (count = 0)
  SELECT
    h.hadm_id,
    h.length_group,
    h.icu_use,
    COALESCE(ic.imaging_count, 0) AS imaging_count
  FROM hf_admissions h
  LEFT JOIN imaging_counts ic
    ON h.hadm_id = ic.hadm_id
)

-- Final aggregation: compute 25th, 50th, 75th percentiles per group
SELECT
  length_group,
  icu_use,
  COUNT(*) AS admissions_in_group,
  (APPROX_QUANTILES(imaging_count, 4))[OFFSET(1)] AS pct_25_imaging_per_admission,
  (APPROX_QUANTILES(imaging_count, 4))[OFFSET(2)] AS pct_50_imaging_per_admission,
  (APPROX_QUANTILES(imaging_count, 4))[OFFSET(3)] AS pct_75_imaging_per_admission
FROM admissions_with_counts
GROUP BY length_group, icu_use
ORDER BY length_group, icu_use;