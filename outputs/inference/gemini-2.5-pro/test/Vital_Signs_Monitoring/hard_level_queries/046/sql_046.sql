WITH
  cohort AS (
    -- Step 1: Define the cohort of male ICU patients, aged 84-94, with ischemic stroke
    SELECT DISTINCT
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON icu.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON icu.hadm_id = dx.hadm_id
    WHERE
      pat.gender = 'M'
      AND (
        pat.anchor_age + EXTRACT(YEAR FROM icu.intime) - pat.anchor_year
      ) BETWEEN 84 AND 94
      AND (dx.icd_code LIKE 'I63%' OR dx.icd_code LIKE '434%') -- Ischemic Stroke (ICD-10) or Occlusion of cerebral arteries (ICD-9)
  ),

  abnormal_events AS (
    -- Step 2a: Identify each abnormal vital sign measurement in the first 72 hours
    SELECT
      c.stay_id,
      CASE
        WHEN ce.itemid = 220045 AND (ce.valuenum < 60 OR ce.valuenum > 100)
        THEN 1 -- Heart Rate
        WHEN ce.itemid = 220210 AND (ce.valuenum < 12 OR ce.valuenum > 20)
        THEN 1 -- Respiratory Rate
        WHEN ce.itemid = 220277 AND ce.valuenum < 94
        THEN 1 -- SpO2
        WHEN ce.itemid IN (220179, 220050) AND (ce.valuenum < 90 OR ce.valuenum > 140)
        THEN 1 -- Systolic BP (NIBP or Arterial)
        WHEN ce.itemid IN (220180, 220051) AND (ce.valuenum < 60 OR ce.valuenum > 90)
        THEN 1 -- Diastolic BP (NIBP or Arterial)
        WHEN ce.itemid = 223762 AND (ce.valuenum < 36 OR ce.valuenum > 38)
        THEN 1 -- Temperature Celsius
        ELSE 0
      END AS is_abnormal
    FROM cohort AS c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON c.stay_id = ce.stay_id
    WHERE
      ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
      AND ce.valuenum IS NOT NULL
      AND ce.itemid IN (
        220045, -- Heart Rate
        220210, -- Respiratory Rate
        220277, -- SpO2
        220179, -- Non Invasive Blood Pressure systolic
        220050, -- Arterial Blood Pressure systolic
        220180, -- Non Invasive Blood Pressure diastolic
        220051, -- Arterial Blood Pressure diastolic
        223762  -- Temperature Celsius
      )
  ),

  patient_scores AS (
    -- Step 2b: Aggregate abnormal events into a score per patient and link outcomes
    SELECT
      c.stay_id,
      icu.los AS icu_los_days,
      adm.hospital_expire_flag,
      COALESCE(SUM(ae.is_abnormal), 0) AS instability_score
    FROM cohort AS c
    LEFT JOIN abnormal_events AS ae
      ON c.stay_id = ae.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      ON c.stay_id = icu.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON c.hadm_id = adm.hadm_id
    GROUP BY
      c.stay_id, icu.los, adm.hospital_expire_flag
  ),

  percentile_result AS (
    -- Step 3: Calculate the percentile rank of an instability score of 80
    SELECT
      SAFE_DIVIDE(
        COUNTIF(instability_score <= 80), COUNT(stay_id)
      ) * 100 AS percentile_rank_of_80
    FROM patient_scores
  ),

  quartile_outcomes AS (
    -- Step 4: Calculate outcomes for the top instability quartile
    WITH
      ranked_scores AS (
        SELECT
          instability_score,
          icu_los_days,
          hospital_expire_flag,
          NTILE(4) OVER (ORDER BY instability_score DESC) AS instability_quartile
        FROM patient_scores
      )
    SELECT
      -- Use PERCENTILE_CONT for median, and AVG for the mortality rate
      -- Use OVER() because we want the aggregate for the entire filtered set (quartile=1)
      DISTINCT PERCENTILE_CONT(
        icu_los_days, 0.5
      ) OVER () AS median_icu_los_top_quartile,
      AVG(hospital_expire_flag) OVER () * 100 AS mortality_rate_top_quartile
    FROM ranked_scores
    WHERE
      instability_quartile = 1
  )

-- Final Step: Combine the results from the percentile and quartile calculations
SELECT
  p.percentile_rank_of_80,
  q.median_icu_los_top_quartile,
  q.mortality_rate_top_quartile
FROM percentile_result AS p
CROSS JOIN quartile_outcomes AS q;