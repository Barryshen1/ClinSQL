WITH
  -- Step 1: Identify the cohort of male patients aged 81-91 who received HFNC in the first 48h of an ICU stay.
  hfnc_stays AS (
    SELECT
      icu.stay_id,
      icu.subject_id,
      icu.hadm_id,
      icu.intime,
      icu.los,
      adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON icu.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON icu.hadm_id = adm.hadm_id
    WHERE
      pat.gender = 'M'
      -- Calculate age at ICU admission and filter
      AND (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year + pat.anchor_age) BETWEEN 81 AND 91
      -- Check for HFNC administration in the first 48 hours
      AND EXISTS (
        SELECT
          1
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        WHERE
          ce.stay_id = icu.stay_id
          AND ce.itemid = 226732  -- itemid for 'O2 Delivery Device(s)'
          -- Use a case-insensitive LIKE to robustly find HFNC
          AND LOWER(ce.value) LIKE '%high flow nasal cannula%'
          AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 48 HOUR)
      )
  ),
  -- Step 2: Calculate the "composite instability score" for each patient in the cohort.
  -- We define this score as the maximum heart rate in the first 48 hours.
  instability_scores AS (
    SELECT
      hs.stay_id,
      hs.los,
      hs.hospital_expire_flag,
      MAX(hr.valuenum) AS instability_score
    FROM hfnc_stays AS hs
    -- Use an INNER JOIN as we only want to score patients with HR measurements
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS hr
      ON hs.stay_id = hr.stay_id
      AND hr.itemid = 220045  -- itemid for 'Heart Rate'
      AND hr.charttime BETWEEN hs.intime AND DATETIME_ADD(hs.intime, INTERVAL 48 HOUR)
      AND hr.valuenum IS NOT NULL
    GROUP BY
      hs.stay_id,
      hs.los,
      hs.hospital_expire_flag
  ),
  -- Step 3: Calculate the percentile rank of a score of 85.
  percentile_calc AS (
    SELECT
      -- Use SAFE_DIVIDE to prevent division by zero errors
      SAFE_DIVIDE(
        COUNTIF(instability_score <= 85) * 100.0,
        COUNT(instability_score)
      ) AS percentile_for_score_85
    FROM instability_scores
  ),
  -- Step 4: Identify the top decile of patients by score and calculate their outcomes.
  top_decile_metrics AS (
    SELECT
      AVG(s.los) AS avg_icu_los_days_top_decile,
      AVG(s.hospital_expire_flag) * 100 AS hospital_mortality_pct_top_decile
    FROM
      (
        SELECT
          los,
          hospital_expire_flag,
          instability_score,
          NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
        FROM instability_scores
        WHERE
          instability_score IS NOT NULL
      ) AS s
    WHERE
      s.decile = 1
  )
-- Final Step: Combine the results from the percentile calculation and top decile metrics.
SELECT
  p.percentile_for_score_85,
  t.avg_icu_los_days_top_decile,
  t.hospital_mortality_pct_top_decile
FROM percentile_calc AS p, top_decile_metrics AS t;