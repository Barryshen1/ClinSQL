WITH
-- all diagnoses with readable titles
diag_with_title AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    dd.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND COALESCE(d.icd_version, 0) = COALESCE(dd.icd_version, dd.icd_version)
  WHERE d.hadm_id IS NOT NULL
),

-- admissions that have at least one pneumonia diagnosis
pneumonia_admissions AS (
  SELECT DISTINCT hadm_id
  FROM diag_with_title
  WHERE lower(COALESCE(long_title, '')) LIKE '%pneumonia%'
),

-- base cohort: male patients age 88-98 with a pneumonia admission and an ICU stay
cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN pneumonia_admissions pa
      ON a.hadm_id = pa.hadm_id
    -- ensure an ICU stay exists for this admission
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
),

-- compute the composite "comorbidity" score = count distinct diagnosis codes (excluding pneumonia codes)
comorbidity_by_hadm AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM
    cohort_admissions c
    LEFT JOIN diag_with_title d
      ON c.hadm_id = d.hadm_id
      -- exclude diagnoses that are labeled as pneumonia so the index diagnosis is not counted
      AND NOT (lower(COALESCE(d.long_title, '')) LIKE '%pneumonia%')
  GROUP BY c.hadm_id
),

-- flags for AKI and ARDS based on diagnosis long_title patterns
flags_by_hadm AS (
  SELECT
    c.hadm_id,
    c.hospital_expire_flag,
    -- AKI flag if any diagnosis mentions acute kidney / acute renal / acute tubular necrosis
    CASE WHEN EXISTS (
      SELECT 1 FROM diag_with_title d
      WHERE d.hadm_id = c.hadm_id
        AND (
          lower(COALESCE(d.long_title, '')) LIKE '%acute kidney%'
          OR lower(COALESCE(d.long_title, '')) LIKE '%acute renal%'
          OR lower(COALESCE(d.long_title, '')) LIKE '%acute tubular necrosis%'
        )
    ) THEN 1 ELSE 0 END AS aki_flag,
    -- ARDS flag if any diagnosis mentions acute respiratory distress or ARDS
    CASE WHEN EXISTS (
      SELECT 1 FROM diag_with_title d
      WHERE d.hadm_id = c.hadm_id
        AND (
          lower(COALESCE(d.long_title, '')) LIKE '%acute respiratory distress%'
          OR lower(COALESCE(d.long_title, '')) LIKE '%ards%'
        )
    ) THEN 1 ELSE 0 END AS ards_flag,
    -- compute survival days for decedents (days between admission and death). For in-hospital deaths deathtime should be present.
    CASE
      WHEN c.hospital_expire_flag = 1 AND c.deathtime IS NOT NULL THEN
        TIMESTAMP_DIFF(c.deathtime, c.admittime, DAY)
      ELSE NULL
    END AS survival_days
  FROM
    cohort_admissions c
),

-- combine comorbidity and flags into one per-hadm row
cohort_measures AS (
  SELECT
    c.hadm_id,
    COALESCE(cb.comorbidity_count, 0) AS composite_score,
    f.hospital_expire_flag,
    f.aki_flag,
    f.ards_flag,
    f.survival_days
  FROM
    cohort_admissions c
    LEFT JOIN comorbidity_by_hadm cb ON c.hadm_id = cb.hadm_id
    LEFT JOIN flags_by_hadm f ON c.hadm_id = f.hadm_id
)

-- final aggregation: cohort size; composite score distribution; outcome rates; median survival for decedents
SELECT
  COUNT(DISTINCT cm.hadm_id) AS cohort_size,
  -- composite score quantiles: use scalar subqueries to extract elements of the quantile array
  (SELECT arr[OFFSET(0)] FROM (SELECT APPROX_QUANTILES(composite_score, 4) AS arr FROM cohort_measures)) AS composite_min,
  (SELECT arr[OFFSET(1)] FROM (SELECT APPROX_QUANTILES(composite_score, 4) AS arr FROM cohort_measures)) AS composite_q1,
  (SELECT arr[OFFSET(2)] FROM (SELECT APPROX_QUANTILES(composite_score, 4) AS arr FROM cohort_measures)) AS composite_median,
  (SELECT arr[OFFSET(3)] FROM (SELECT APPROX_QUANTILES(composite_score, 4) AS arr FROM cohort_measures)) AS composite_q3,
  (SELECT arr[OFFSET(4)] FROM (SELECT APPROX_QUANTILES(composite_score, 4) AS arr FROM cohort_measures)) AS composite_max,
  -- outcome rates (proportion of admissions)
  SAFE_DIVIDE(SUM(cm.hospital_expire_flag), COUNT(DISTINCT cm.hadm_id)) AS inhospital_mortality_rate,
  SAFE_DIVIDE(SUM(cm.aki_flag), COUNT(DISTINCT cm.hadm_id)) AS aki_rate,
  SAFE_DIVIDE(SUM(cm.ards_flag), COUNT(DISTINCT cm.hadm_id)) AS ards_rate,
  -- median survival days among decedents: extract median from APPROX_QUANTILES(survival_days, 2) using SAFE_OFFSET
  (SELECT arr[SAFE_OFFSET(1)] FROM (SELECT APPROX_QUANTILES(survival_days, 2) AS arr FROM cohort_measures WHERE survival_days IS NOT NULL)) AS median_survival_days_decedents
FROM
  cohort_measures cm;