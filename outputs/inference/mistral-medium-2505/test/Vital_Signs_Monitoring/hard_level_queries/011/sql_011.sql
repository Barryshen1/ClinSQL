WITH
-- Get female patients aged 55-65
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year,
    dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 55 AND 65
),

-- Get pneumonia diagnoses (ICD-9/10 codes for pneumonia)
pneumonia_diagnoses AS (
  SELECT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE
    (dd.icd_code LIKE 'J12%' OR dd.icd_code LIKE 'J13%' OR dd.icd_code LIKE 'J14%'
     OR dd.icd_code LIKE 'J15%' OR dd.icd_code LIKE 'J16%' OR dd.icd_code LIKE 'J17%'
     OR dd.icd_code LIKE 'J18%' OR dd.icd_code LIKE '480%' OR dd.icd_code LIKE '481%'
     OR dd.icd_code LIKE '482%' OR dd.icd_code LIKE '483%' OR dd.icd_code LIKE '484%'
     OR dd.icd_code LIKE '485%' OR dd.icd_code LIKE '486%')
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    i.hadm_id = a.hadm_id
  WHERE
    i.subject_id IN (SELECT subject_id FROM female_patients)
    AND i.hadm_id IN (SELECT hadm_id FROM pneumonia_diagnoses)
),

-- Calculate instability score (proxy: sum of abnormal lab values in first 24 hours)
instability_scores AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.icu_los,
    s.hospital_expire_flag,
    -- Example instability score calculation (simplified for demonstration)
    -- In practice, this would be a more sophisticated calculation
    SUM(CASE
        WHEN (l.itemid IN (50885, 50886) AND l.valuenum > 2.0) THEN 10 -- High lactate
        WHEN (l.itemid IN (220045, 220046) AND l.valuenum < 90) THEN 15 -- Low mean BP
        WHEN (l.itemid IN (220050, 220051) AND l.valuenum > 100) THEN 5 -- High heart rate
        ELSE 0
      END) AS instability_score
  FROM
    icu_stays s
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` l
  ON
    s.stay_id = l.stay_id
    AND l.charttime BETWEEN s.icu_intime AND DATETIME_ADD(s.icu_intime, INTERVAL 24 HOUR)
  GROUP BY
    s.subject_id, s.hadm_id, s.stay_id, s.icu_los, s.hospital_expire_flag
),

-- Calculate percentiles
percentile_calc AS (
  SELECT
    instability_score,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile
  FROM
    instability_scores
),

-- Get the 90th percentile threshold
percentile_threshold AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.9) OVER() AS threshold_90th
  FROM
    instability_scores
  LIMIT 1
),

-- Get the most unstable decile (top 10%)
most_unstable_decile AS (
  SELECT
    i.instability_score,
    i.icu_los,
    i.hospital_expire_flag
  FROM
    instability_scores i
  CROSS JOIN
    percentile_threshold p
  WHERE
    i.instability_score >= p.threshold_90th
)

-- Final results
SELECT
  -- Percentile for score of 60 (using approximate method)
  (SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(60)] FROM instability_scores) AS percentile_for_score_60,

  -- Average ICU LOS for most unstable decile
  AVG(icu_los) AS avg_icu_los_most_unstable,

  -- Mortality rate for most unstable decile
  AVG(CAST(hospital_expire_flag AS INT64)) AS mortality_rate_most_unstable

FROM
  most_unstable_decile;