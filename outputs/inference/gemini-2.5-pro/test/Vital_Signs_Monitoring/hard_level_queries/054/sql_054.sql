WITH
-- 1. Identify the first ICU stay for each hospital admission
first_icu_stays AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    los,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS stay_rank
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- 2. Identify hospital admissions with a diagnosis of Acute Respiratory Failure (ARF)
arf_hadm_ids AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 for Acute Respiratory Failure
    (icd_version = 9 AND icd_code = '51881')
    -- ICD-10 for Acute Respiratory Failure (J96.0x)
    OR (icd_version = 10 AND STARTS_WITH(icd_code, 'J960'))
),

-- 3. Define the cohorts by joining demographics, admissions, and the ARF diagnosis
cohorts AS (
  SELECT
    fs.subject_id,
    fs.stay_id,
    fs.hadm_id,
    fs.intime,
    fs.los,
    adm.hospital_expire_flag,
    -- Define the target cohort: Male, Age 82-92, with ARF
    (
      p.gender = 'M'
      AND (EXTRACT(YEAR FROM fs.intime) - p.anchor_year + p.anchor_age) BETWEEN 82 AND 92
      AND arf.hadm_id IS NOT NULL
    ) AS is_target_cohort
  FROM first_icu_stays AS fs
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON fs.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON fs.hadm_id = adm.hadm_id
  LEFT JOIN arf_hadm_ids AS arf
    ON fs.hadm_id = arf.hadm_id
  WHERE fs.stay_rank = 1 -- Only include the first ICU stay
),

-- 4. Get Heart Rate and Mean Arterial Pressure values in the first 72 hours
vitals_in_window AS (
  SELECT
    c.stay_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum
  FROM cohorts AS c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON c.stay_id = ce.stay_id
  WHERE
    -- Vitals within the first 72 hours of ICU admission
    ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND ce.itemid IN (
      220045, -- Heart Rate
      220052, -- Arterial Blood Pressure mean
      220181, -- Non Invasive Blood Pressure mean
      225312  -- ART BP mean
    )
    AND ce.valuenum IS NOT NULL AND ce.valuenum > 0
),

-- 5. Aggregate vitals into hourly averages to normalize for charting frequency
hourly_vitals AS (
  SELECT
    stay_id,
    TIMESTAMP_TRUNC(charttime, HOUR) AS hour,
    -- Pivot and average vitals per hour
    AVG(CASE WHEN itemid = 220045 THEN valuenum END) AS hr,
    -- Coalesce the different MAP measurements, prioritizing arterial
    COALESCE(
      AVG(CASE WHEN itemid IN (220052, 225312) THEN valuenum END), -- Average all arterial MAPs
      AVG(CASE WHEN itemid = 220181 THEN valuenum END)
    ) AS map
  FROM vitals_in_window
  GROUP BY stay_id, hour
),

-- 6. Calculate the average instability "burden" for each patient over the 72h period
patient_burden AS (
  SELECT
    stay_id,
    -- The burden is the average of the hourly instability scores
    AVG(
      (CASE WHEN map < 65 THEN 1 ELSE 0 END)
      + (CASE WHEN hr > 100 THEN 1 ELSE 0 END)
    ) AS avg_instability_burden
  FROM hourly_vitals
  WHERE hr IS NOT NULL AND map IS NOT NULL -- Only include hours with both measurements
  GROUP BY stay_id
),

-- 7. Join cohort information with the calculated burden scores
final_cohort_data AS (
  SELECT
    c.stay_id,
    c.is_target_cohort,
    c.los,
    c.hospital_expire_flag,
    pb.avg_instability_burden
  FROM cohorts AS c
  LEFT JOIN patient_burden AS pb
    ON c.stay_id = pb.stay_id
)

-- 8. Final aggregation and reporting for the Target cohort
SELECT
  'Target' AS cohort_group,
  COUNT(stay_id) AS patient_count,
  APPROX_QUANTILES(avg_instability_burden, 4 IGNORE NULLS)[SAFE_OFFSET(1)] AS p25_instability_burden,
  APPROX_QUANTILES(avg_instability_burden, 4 IGNORE NULLS)[SAFE_OFFSET(2)] AS median_instability_burden,
  APPROX_QUANTILES(avg_instability_burden, 4 IGNORE NULLS)[SAFE_OFFSET(3)] AS p75_instability_burden,
  (
    APPROX_QUANTILES(avg_instability_burden, 4 IGNORE NULLS)[SAFE_OFFSET(3)]
    - APPROX_QUANTILES(avg_instability_burden, 4 IGNORE NULLS)[SAFE_OFFSET(1)]
  ) AS iqr_instability_burden,
  AVG(avg_instability_burden) AS avg_instability_burden,
  AVG(los) AS avg_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate_percent
FROM final_cohort_data
WHERE is_target_cohort

UNION ALL

-- 9. Final aggregation and reporting for the General cohort
SELECT
  'General' AS cohort_group,
  COUNT(stay_id) AS patient_count,
  NULL AS p25_instability_burden,
  NULL AS median_instability_burden,
  NULL AS p75_instability_burden,
  NULL AS iqr_instability_burden,
  AVG(avg_instability_burden) AS avg_instability_burden,
  AVG(los) AS avg_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate_percent
FROM final_cohort_data

ORDER BY cohort_group DESC; -- Puts 'Target' group first;