WITH
  cohort AS (
    -- Step 1: Identify ICU stays for male patients aged 88-98
    SELECT
      p.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime,
      DATETIME_ADD(icu.intime, INTERVAL 72 HOUR) AS endtime_72h,
      icu.los
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS p ON icu.subject_id = p.subject_id
    WHERE
      p.gender = 'M'
      AND (
        EXTRACT(YEAR FROM icu.intime) - p.anchor_year + p.anchor_age
      ) BETWEEN 88 AND 98
  ),
  instability_scores_calc AS (
    -- Step 2: Calculate the instability score for each stay in the cohort
    SELECT
      c.stay_id,
      -- The instability score is the sum of coefficients of variation for key vitals, scaled by 100.
      -- COALESCE is used to treat missing vitals as 0 variability.
      (
        COALESCE(
          SAFE_DIVIDE(
            STDDEV_SAMP(CASE WHEN ce.itemid = 220045 THEN ce.valuenum END), -- Heart Rate
            AVG(CASE WHEN ce.itemid = 220045 THEN ce.valuenum END)
          ),
          0
        )
        + COALESCE(
          SAFE_DIVIDE(
            STDDEV_SAMP(CASE WHEN ce.itemid = 220052 THEN ce.valuenum END), -- Arterial BP Mean
            AVG(CASE WHEN ce.itemid = 220052 THEN ce.valuenum END)
          ),
          0
        )
        + COALESCE(
          SAFE_DIVIDE(
            STDDEV_SAMP(CASE WHEN ce.itemid = 220210 THEN ce.valuenum END), -- Respiratory Rate
            AVG(CASE WHEN ce.itemid = 220210 THEN ce.valuenum END)
          ),
          0
        )
        + COALESCE(
          SAFE_DIVIDE(
            STDDEV_SAMP(CASE WHEN ce.itemid = 220277 THEN ce.valuenum END), -- O2 saturation peripheral
            AVG(CASE WHEN ce.itemid = 220277 THEN ce.valuenum END)
          ),
          0
        )
      ) * 100 AS instability_score
    FROM
      cohort AS c
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON c.stay_id = ce.stay_id
    WHERE
      ce.charttime BETWEEN c.intime AND c.endtime_72h
      AND ce.itemid IN (
        220045, -- Heart Rate
        220052, -- Arterial Blood Pressure mean
        220210, -- Respiratory Rate
        220277  -- O2 saturation peripheral
      )
      AND ce.valuenum IS NOT NULL
      AND ce.valuenum > 0 -- Basic cleaning to remove invalid values
    GROUP BY
      c.stay_id
    -- Ensure the score is based on a reasonable amount of data
    HAVING
      COUNT(DISTINCT ce.itemid) >= 2 AND COUNT(ce.valuenum) > 10
  ),
  final_data AS (
    -- Step 3: Combine scores with outcomes and rank into quartiles
    SELECT
      c.stay_id,
      c.los,
      adm.hospital_expire_flag,
      isc.instability_score,
      NTILE(4) OVER (
        ORDER BY
          isc.instability_score DESC
      ) AS instability_quartile
    FROM
      cohort AS c
    INNER JOIN
      instability_scores_calc AS isc ON c.stay_id = isc.stay_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON c.hadm_id = adm.hadm_id
    WHERE
      isc.instability_score IS NOT NULL
  )
-- Step 4: Calculate the final metrics from the prepared data
SELECT
  (
    SELECT
      (
        COUNTIF(instability_score < 85) * 100.0
      ) / COUNT(instability_score)
    FROM
      final_data
  ) AS percentile_of_score_85,
  (
    SELECT
      AVG(los)
    FROM
      final_data
    WHERE
      instability_quartile = 1
  ) AS avg_icu_los_for_most_unstable_quartile,
  (
    SELECT
      AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100
    FROM
      final_data
    WHERE
      instability_quartile = 1
  ) AS hospital_mortality_percent_for_most_unstable_quartile;