WITH ich_cohort AS (
  -- ICH cohort: females, age 56-66, with ICH diagnosis and ICU stay
  SELECT DISTINCT 
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + 1 AS age_at_admit,
    -- First ICU stay
    first_stay.stay_id,
    first_stay.intime,
    first_stay.los AS icu_los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN (
    -- First ICU stay per subject/hadm
    SELECT subject_id, hadm_id, stay_id, intime, los,
           ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) first_stay
    ON a.subject_id = first_stay.subject_id 
    AND a.hadm_id = first_stay.hadm_id 
    AND first_stay.rn = 1
  WHERE p.gender = 'F'
    AND p.anchor_year IS NOT NULL
    AND ((EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + 1) BETWEEN 56 AND 66
    AND (
      (d.icd_version = 'ICD-9' AND d.icd_code LIKE '431%') OR
      (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'I61%')
    )
),

overall_icu AS (
  -- Overall female ICU patients aged 56-66 (for comparison)
  SELECT 
    p.subject_id,
    first_stay.stay_id,
    first_stay.intime,
    first_stay.los AS icu_los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN (
    SELECT subject_id, hadm_id, stay_id, intime, los,
           ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) first_stay
    ON a.subject_id = first_stay.subject_id 
    AND a.hadm_id = first_stay.hadm_id 
    AND first_stay.rn = 1
  WHERE p.gender = 'F'
    AND p.anchor_year IS NOT NULL
    AND ((EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + 1) BETWEEN 56 AND 66
),

diagnostic_events AS (
  -- Events in first 72h for ICH cohort
  SELECT subject_id, COUNT(DISTINCT itemid) AS intensity
  FROM (
    -- Chartevents in first 72h of first ICU stay
    SELECT ce.subject_id, ce.itemid
    FROM ich_cohort ic
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON ic.stay_id = ce.stay_id
    WHERE ce.charttime >= ic.intime
      AND ce.charttime <= ic.intime + INTERVAL 3 DAY
      AND ce.itemid IS NOT NULL
      AND ce.valuenum IS NOT NULL  -- Valid measurements only

    UNION ALL

    -- Labevents in first 72h (hospital-level, during ICU window)
    SELECT le.subject_id, CAST(le.itemid AS STRING) AS itemid
    FROM ich_cohort ic
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON ic.subject_id = le.subject_id AND ic.hadm_id = le.hadm_id
    WHERE le.charttime >= ic.intime
      AND le.charttime <= ic.intime + INTERVAL 3 DAY
      AND le.itemid IS NOT NULL
      AND le.valuenum IS NOT NULL  -- Valid labs only
  ) events
  GROUP BY subject_id
),

ich_aggregates AS (
  SELECT 
    -- Intensity
    PERCENTILE_CONT(0.95, COALESCE(de.intensity, 0)) OVER() AS p95_intensity,
    -- LOS
    AVG(ic.icu_los) AS mean_los_days,
    PERCENTILE_CONT(0.5, ic.icu_los) OVER() AS median_los_days,
    -- Mortality
    AVG(CAST(ic.hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM ich_cohort ic
  LEFT JOIN diagnostic_events de ON ic.subject_id = de.subject_id
),

overall_aggregates AS (
  SELECT 
    -- LOS
    AVG(icu_los) AS mean_los_days,
    PERCENTILE_CONT(0.5, icu_los) OVER() AS median_los_days,
    -- Mortality
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM overall_icu
)

-- Final results: ICH vs overall
SELECT 
  'ICH Cohort' AS cohort,
  p95_intensity,
  mean_los_days,
  median_los_days,
  mortality_rate
FROM ich_aggregates

UNION ALL

SELECT 
  'Overall ICU' AS cohort,
  NULL AS p95_intensity,  -- Not computed for overall
  mean_los_days,
  median_los_days,
  mortality_rate
FROM overall_aggregates;