WITH
  -- Step 1: Define the cohort of post-operative male patients within the specified age range.
  cohort AS (
    SELECT
      pat.subject_id,
      icu.hadm_id,
      icu.stay_id,
      -- Calculate age at ICU admission for filtering
      DATETIME_DIFF(icu.intime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) + pat.anchor_age AS age_at_icu_admission,
      icu.intime,
      icu.los,
      adm.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON icu.subject_id = pat.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON icu.hadm_id = adm.hadm_id
    WHERE
      -- Filter for male patients aged 63-73
      pat.gender = 'M'
      AND (
        DATETIME_DIFF(icu.intime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) + pat.anchor_age
      ) BETWEEN 63 AND 73
      -- Filter for post-operative patients by checking for any surgical service during the admission
      AND EXISTS (
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_hosp.services` AS s
        WHERE
          s.hadm_id = icu.hadm_id AND s.curr_service LIKE '%SURG%'
      )
  ),
  -- Step 2: Gather all relevant vital signs for the cohort to avoid multiple scans of the large chartevents table.
  all_vitals AS (
    SELECT
      c.stay_id,
      ce.charttime,
      ce.itemid,
      ce.valuenum,
      -- Flag if the measurement is within the first 24 hours of the ICU stay for the instability score
      (ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)) AS is_first_24h
    FROM
      cohort AS c
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON c.stay_id = ce.stay_id
    WHERE
      ce.itemid IN (
        220045, -- Heart Rate
        220179, -- Non Invasive Blood Pressure systolic
        220050, -- Arterial Blood Pressure systolic
        220052, -- Arterial Blood Pressure mean
        225312, -- ART BP mean
        220210, -- Respiratory Rate
        220277, -- O2 saturation pulseoxymetry
        223762, -- Temperature Celsius
        223761 -- Temperature Fahrenheit
      )
      AND ce.valuenum IS NOT NULL
  ),
  -- Step 3: Calculate the instability score and episode flags for each patient from the collected vitals.
  patient_metrics AS (
    SELECT
      stay_id,
      -- Instability Score: Count of distinct hours in the first 24h with any unstable vital
      COUNT(
        DISTINCT CASE WHEN is_first_24h AND is_unstable_measurement = 1 THEN DATETIME_TRUNC(charttime, HOUR) ELSE NULL END
      ) AS instability_score,
      -- Flag for fever episode (>38.5 C) during the entire stay
      MAX(CASE WHEN temp_c > 38.5 THEN 1 ELSE 0 END) AS has_fever,
      -- Flag for low SpO2 episode (<90%) during the entire stay
      MAX(CASE WHEN itemid = 220277 AND valuenum < 90 THEN 1 ELSE 0 END) AS has_low_spo2,
      -- Flag for high RR episode (>20/min) during the entire stay
      MAX(CASE WHEN itemid = 220210 AND valuenum > 20 THEN 1 ELSE 0 END) AS has_high_rr
    FROM
      (
        SELECT
          stay_id,
          charttime,
          itemid,
          valuenum,
          is_first_24h,
          -- Normalize temperature to Celsius for consistent comparison
          IF(itemid = 223761, (valuenum - 32) * 5 / 9, valuenum) AS temp_c,
          -- Flag '1' for any measurement meeting instability criteria
          CASE
            WHEN itemid = 220045 AND (valuenum > 120 OR valuenum < 50) THEN 1 -- Heart Rate
            WHEN itemid IN (220179, 220050) AND valuenum < 90 THEN 1 -- Systolic BP
            WHEN itemid IN (220052, 225312) AND valuenum < 65 THEN 1 -- Mean Arterial BP
            WHEN itemid = 220210 AND valuenum > 25 THEN 1 -- Respiratory Rate (>25 for score)
            WHEN itemid = 220277 AND valuenum < 90 THEN 1 -- SpO2
            WHEN itemid = 223762 AND (valuenum > 38.5 OR valuenum < 36) THEN 1 -- Temp C
            WHEN itemid = 223761 AND (((valuenum - 32) * 5 / 9 > 38.5) OR ((valuenum - 32) * 5 / 9 < 36)) THEN 1 -- Temp F
            ELSE 0
          END AS is_unstable_measurement
        FROM
          all_vitals
      )
    GROUP BY
      stay_id
  ),
  -- Step 4: Combine cohort data with calculated metrics and assign instability quartiles.
  final_data AS (
    SELECT
      c.stay_id,
      c.los,
      c.hospital_expire_flag,
      COALESCE(pm.instability_score, 0) AS instability_score,
      COALESCE(pm.has_fever, 0) AS has_fever,
      COALESCE(pm.has_low_spo2, 0) AS has_low_spo2,
      COALESCE(pm.has_high_rr, 0) AS has_high_rr,
      -- Assign quartiles based on instability score. NTILE=1 is the highest instability group.
      NTILE(4) OVER (
        ORDER BY
          COALESCE(pm.instability_score, 0) DESC
      ) AS instability_quartile
    FROM
      cohort AS c
    LEFT JOIN
      patient_metrics AS pm
      ON c.stay_id = pm.stay_id
  )
-- Step 5: Final aggregation to compare the top quartile with the rest of the cohort.
SELECT
  CASE
    WHEN instability_quartile = 1 THEN 'Top Quartile of Instability'
    ELSE 'Other Quartiles (1-3)'
  END AS patient_group,
  COUNT(stay_id) AS number_of_patients,
  -- Calculate 95th percentile instability score, only for the top quartile group
  APPROX_QUANTILES(
    CASE WHEN instability_quartile = 1 THEN instability_score ELSE NULL END, 100
  ) [
OFFSET
  (95) ] AS p95_instability_score_top_quartile,
  AVG(has_fever) * 100 AS percent_with_fever,
  AVG(has_low_spo2) * 100 AS percent_with_spo2_lt_90,
  AVG(has_high_rr) * 100 AS percent_with_rr_gt_20,
  AVG(los) AS avg_icu_los_days,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent
FROM
  final_data
GROUP BY
  patient_group
ORDER BY
  -- Show the 'Top Quartile' group first for easy comparison
  patient_group DESC;