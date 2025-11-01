WITH
-- ICU stays for male patients age 37-47 (using anchor_age)
eligible_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),

-- Stays with documentation of noninvasive ventilation (CPAP/BiPAP/NIV) in chartevents
niv_from_chartevents AS (
  SELECT DISTINCT
    ce.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    ce.stay_id IS NOT NULL
    AND (
      LOWER(COALESCE(CAST(ce.value AS STRING), '')) LIKE '%cpap%'
      OR LOWER(COALESCE(CAST(ce.value AS STRING), '')) LIKE '%bipap%'
      OR LOWER(COALESCE(CAST(ce.value AS STRING), '')) LIKE '%noninvasive%'
      OR LOWER(COALESCE(CAST(ce.value AS STRING), '')) LIKE '%niv%'
      OR LOWER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%cpap%'
      OR LOWER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%bipap%'
      OR LOWER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%noninvasive%'
      OR LOWER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%niv%'
    )
),

-- Also check procedureevents for NIV mentions (some sites document procedures)
niv_from_procedureevents AS (
  SELECT DISTINCT
    pe.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE
    pe.stay_id IS NOT NULL
    AND (
      LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%cpap%'
      OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%bipap%'
      OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%noninvasive%'
      OR LOWER(COALESCE(CAST(pe.value AS STRING), '')) LIKE '%niv%'
      OR LOWER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%cpap%'
      OR LOWER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%bipap%'
      OR LOWER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%noninvasive%'
      OR LOWER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%niv%'
    )
),

-- Combine NIV stay IDs
niv_stays AS (
  SELECT DISTINCT stay_id FROM niv_from_chartevents
  UNION DISTINCT
  SELECT DISTINCT stay_id FROM niv_from_procedureevents
),

-- NIV-eligible ICU stays: intersection of eligible_stays and detected NIV stays
eligible_niv_stays AS (
  SELECT
    s.*
  FROM
    eligible_stays s
  JOIN
    niv_stays n
  ON s.stay_id = n.stay_id
),

-- For each eligible stay, compute the maximum numeric diastolic blood pressure recorded during the stay.
-- We identify diastolic BP items by d_items.label containing 'diastolic'
max_dbp_per_stay AS (
  SELECT
    ce.stay_id,
    MAX(ce.valuenum) AS max_dbp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN
    eligible_niv_stays s
    ON ce.stay_id = s.stay_id
       AND ce.charttime BETWEEN s.intime AND s.outtime
  WHERE
    ce.valuenum IS NOT NULL
    AND LOWER(COALESCE(CAST(di.label AS STRING), '')) LIKE '%diastolic%'
  GROUP BY
    ce.stay_id
)

-- Final: compute the 25th percentile (approximate) of the per-stay maxima
SELECT
  -- approximate 25th percentile
  APPROX_QUANTILES(max_dbp, 100)[OFFSET(25)] AS dbp_25th_percentile,
  -- additional transparency: number of stays included and sample statistics
  COUNT(*) AS num_stays_included,
  MIN(max_dbp) AS min_max_dbp,
  MAX(max_dbp) AS max_max_dbp,
  ROUND(AVG(max_dbp), 2) AS mean_max_dbp
FROM
  max_dbp_per_stay;