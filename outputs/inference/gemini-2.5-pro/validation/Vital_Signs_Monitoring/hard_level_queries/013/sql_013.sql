WITH
  -- Step 1: Identify ICU stays for male patients and calculate their age
  cohort_base AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.hospital_expire_flag,
      i.stay_id,
      i.intime,
      i.los,
      -- Calculate age at the time of ICU admission
      (EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age) AS age_at_icu_admission,
      ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.icustays` AS i
      ON a.hadm_id = i.hadm_id
    WHERE
      p.gender = 'M'
  ),
  -- Step 2: Filter for first ICU stays aged 68-78 with a multi-trauma diagnosis
  trauma_cohort AS (
    SELECT DISTINCT -- Ensure one row per stay
      cb.subject_id,
      cb.hadm_id,
      cb.stay_id,
      cb.intime,
      cb.los,
      cb.hospital_expire_flag
    FROM
      cohort_base AS cb
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON cb.hadm_id = dx.hadm_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
      ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
    WHERE
      cb.rn = 1  -- Only the first ICU stay for each patient
      AND cb.age_at_icu_admission BETWEEN 68 AND 78 -- Filter on calculated age
      AND (
        -- Use LOWER() and LIKE for case-insensitive matching in BigQuery
        LOWER(ddx.long_title) LIKE '%multiple trauma%' OR LOWER(ddx.long_title) LIKE '%multiple injuries%'
      )
  ),
  -- Step 3: Extract relevant vital signs from the first 24 hours of the ICU stay
  vitals_first_24h AS (
    SELECT
      tc.stay_id,
      ce.itemid,
      ce.valuenum
    FROM
      trauma_cohort AS tc
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON tc.stay_id = ce.stay_id
    WHERE
      ce.charttime BETWEEN tc.intime AND DATETIME_ADD(tc.intime, INTERVAL 24 HOUR)
      AND ce.itemid IN (
        220045,  -- Heart Rate
        220179,  -- Non Invasive Blood Pressure systolic
        220050,  -- Arterial Blood Pressure systolic
        220210   -- Respiratory Rate
      )
      AND ce.valuenum IS NOT NULL AND ce.valuenum > 0
  ),
  -- Step 4: Flag each vital sign measurement as an instability episode (1 if abnormal, 0 otherwise)
  instability_episodes AS (
    SELECT
      stay_id,
      CASE WHEN itemid = 220045 AND valuenum > 100 THEN 1 ELSE 0 END AS tachycardia_episode,
      CASE WHEN itemid IN (220179, 220050) AND valuenum < 90 THEN 1 ELSE 0 END AS hypotension_episode,
      CASE WHEN itemid = 220210 AND valuenum > 20 THEN 1 ELSE 0 END AS tachypnea_episode
    FROM
      vitals_first_24h
  ),
  -- Step 5: Sum the episodes for each stay to create the instability score
  instability_scores AS (
    SELECT
      stay_id,
      SUM(tachycardia_episode) AS tachycardia_episodes,
      SUM(hypotension_episode) AS hypotension_episodes,
      SUM(tachypnea_episode) AS tachypnea_episodes,
      (SUM(tachycardia_episode) + SUM(hypotension_episode) + SUM(tachypnea_episode)) AS instability_score
    FROM
      instability_episodes
    GROUP BY
      stay_id
  ),
  -- Step 6: Join scores back to the full cohort, defaulting to 0 for stays with no vital signs
  final_cohort_data AS (
    SELECT
      tc.stay_id,
      tc.los,
      tc.hospital_expire_flag,
      COALESCE(sc.tachycardia_episodes, 0) AS tachycardia_episodes,
      COALESCE(sc.hypotension_episodes, 0) AS hypotension_episodes,
      COALESCE(sc.tachypnea_episodes, 0) AS tachypnea_episodes,
      COALESCE(sc.instability_score, 0) AS instability_score
    FROM
      trauma_cohort AS tc
    LEFT JOIN
      instability_scores AS sc
      ON tc.stay_id = sc.stay_id
  ),
  -- Step 7: Rank the cohort by instability score to find quartiles and the top decile
  ranked_cohort AS (
    SELECT
      *,
      NTILE(4) OVER (ORDER BY instability_score) AS quartile,
      NTILE(10) OVER (ORDER BY instability_score DESC) AS decile_rank
    FROM
      final_cohort_data
  )
-- Final Step: Combine the two requested analyses into a single report
-- Part 1: Quartile Analysis
SELECT
  'Quartile Analysis' AS report_section,
  CAST(quartile AS STRING) AS category,
  COUNT(stay_id) AS count_patients,
  ROUND(AVG(instability_score), 2) AS mean_instability_score,
  ROUND(AVG(los), 2) AS mean_icu_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_rate_percent,
  NULL AS mean_tachycardia_episodes,
  NULL AS mean_hypotension_episodes,
  NULL AS mean_tachypnea_episodes
FROM
  ranked_cohort
GROUP BY
  quartile
UNION ALL
-- Part 2: Top Decile Analysis
SELECT
  'Top Decile Breakdown' AS report_section,
  'Top 10%' AS category,
  COUNT(stay_id) AS count_patients,
  ROUND(AVG(instability_score), 2) AS mean_instability_score,
  NULL AS mean_icu_los_days,
  NULL AS mortality_rate_percent,
  ROUND(AVG(tachycardia_episodes), 2) AS mean_tachycardia_episodes,
  ROUND(AVG(hypotension_episodes), 2) AS mean_hypotension_episodes,
  ROUND(AVG(tachypnea_episodes), 2) AS mean_tachypnea_episodes
FROM
  ranked_cohort
WHERE
  decile_rank = 1
ORDER BY
  report_section DESC,
  category;