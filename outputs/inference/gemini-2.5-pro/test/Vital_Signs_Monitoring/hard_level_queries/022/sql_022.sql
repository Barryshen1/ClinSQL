WITH
  -- Step 1: Identify the cohort of male ICU patients aged 85-95 with acute respiratory failure.
  cohort AS (
    SELECT
      p.subject_id,
      adm.hadm_id,
      icu.stay_id,
      icu.intime,
      icu.los,
      adm.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON icu.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON icu.hadm_id = adm.hadm_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 85 AND 95
      AND EXISTS (
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        WHERE
          dx.hadm_id = adm.hadm_id
          AND (
            (dx.icd_code = '51881' AND dx.icd_version = 9) -- Acute respiratory failure (ICD-9)
            OR (dx.icd_code LIKE 'J960%' AND dx.icd_version = 10) -- Acute respiratory failure (ICD-10)
          )
      )
  ),
  -- Step 2: Identify abnormal vital signs in the first 24 hours for the cohort.
  abnormal_vitals AS (
    SELECT
      c.stay_id,
      -- Flag each abnormal vital sign measurement as 1, otherwise 0.
      CASE
        WHEN ce.itemid = 220045 AND (ce.valuenum < 60 OR ce.valuenum > 100) -- Heart Rate
        THEN 1
        WHEN ce.itemid = 220210 AND (ce.valuenum < 12 OR ce.valuenum > 20) -- Respiratory Rate
        THEN 1
        WHEN ce.itemid = 220277 AND ce.valuenum < 92 -- SpO2
        THEN 1
        WHEN ce.itemid = 220179 AND (ce.valuenum < 90 OR ce.valuenum > 160) -- NBP Systolic
        THEN 1
        WHEN ce.itemid = 220180 AND (ce.valuenum < 60 OR ce.valuenum > 100) -- NBP Diastolic
        THEN 1
        ELSE 0
      END AS is_abnormal
    FROM
      cohort AS c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON c.stay_id = ce.stay_id
    WHERE
      -- Filter to the first 24 hours of the ICU stay
      ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
      -- Filter for relevant vital sign itemids
      AND ce.itemid IN (
        220045, -- Heart Rate
        220210, -- Respiratory Rate
        220277, -- O2 saturation pulseoxymetry
        220179, -- Non Invasive Blood Pressure systolic
        220180  -- Non Invasive Blood Pressure diastolic
      )
      AND ce.valuenum IS NOT NULL
  ),
  -- Step 3: Calculate the instability score by summing abnormal events for each stay.
  instability_scores AS (
    SELECT
      stay_id,
      SUM(is_abnormal) AS instability_score
    FROM
      abnormal_vitals
    GROUP BY
      stay_id
  ),
  -- Step 4: Combine the cohort with their scores and assign instability quartiles.
  cohort_with_scores AS (
    SELECT
      c.stay_id,
      c.los,
      c.hospital_expire_flag,
      -- If a patient has no vitals, their score is 0.
      COALESCE(s.instability_score, 0) AS instability_score,
      -- Assign quartiles based on score; highest scores (most unstable) are in quartile 1.
      NTILE(4) OVER (ORDER BY COALESCE(s.instability_score, 0) DESC) AS instability_quartile
    FROM
      cohort AS c
    LEFT JOIN instability_scores AS s
      ON c.stay_id = s.stay_id
  ),
  -- Step 5: Calculate the final metrics.
  -- A) Average LOS and mortality for the most unstable quartile.
  top_quartile_stats AS (
    SELECT
      AVG(los) AS avg_los_top_quartile,
      AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate_top_quartile
    FROM
      cohort_with_scores
    WHERE
      instability_quartile = 1 -- Filter for the most unstable 25% of patients
  ),
  -- B) Percentile rank of a score of 85.
  percentile_rank_calc AS (
    SELECT
      -- Calculate the percentage of the cohort with a score at or below 85.
      SAFE_DIVIDE(
        COUNTIF(instability_score <= 85),
        COUNT(stay_id)
      ) * 100 AS percentile_rank_of_score_85
    FROM
      cohort_with_scores
  )
-- Final Step: Combine the results into a single output row.
SELECT
  pr.percentile_rank_of_score_85,
  tq.avg_los_top_quartile,
  tq.mortality_rate_top_quartile
FROM
  percentile_rank_calc AS pr,
  top_quartile_stats AS tq;