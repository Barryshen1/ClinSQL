WITH
  -- 1. Define the cohort: Male patients, 45-55 years old, with a Heart Failure diagnosis.
  hf_cohort AS (
    SELECT
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime,
      icu.los
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat ON icu.subject_id = pat.subject_id
    -- Filter for Heart Failure diagnosis using ICD codes
    WHERE
      EXISTS (
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        WHERE
          dx.hadm_id = icu.hadm_id
          AND (
            (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
            OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
          )
      )
      -- Filter for gender
      AND pat.gender = 'M'
      -- Filter for age at the time of ICU admission
      AND (
        pat.anchor_age + EXTRACT(YEAR FROM icu.intime) - pat.anchor_year
      ) BETWEEN 45 AND 55
  ),
  -- 2. Get hourly-averaged vital signs for the first 72 hours for the HF cohort.
  hourly_vitals_hf AS (
    SELECT
      hf.stay_id,
      DATETIME_TRUNC(ce.charttime, HOUR) AS chart_hour,
      AVG(
        CASE WHEN ce.itemid = 220045 THEN ce.valuenum END
      ) AS avg_hr,
      -- Prioritize invasive MAP (220052) over non-invasive (220181)
      COALESCE(
        AVG(CASE WHEN ce.itemid = 220052 THEN ce.valuenum END),
        AVG(CASE WHEN ce.itemid = 220181 THEN ce.valuenum END)
      ) AS avg_map,
      AVG(
        CASE WHEN ce.itemid = 220210 THEN ce.valuenum END
      ) AS avg_rr
    FROM
      hf_cohort AS hf
      INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON hf.stay_id = ce.stay_id
    WHERE
      ce.itemid IN (
        220045, -- Heart Rate
        220052, -- Arterial BP Mean
        220181, -- NBP Mean
        220210  -- Respiratory Rate
      )
      AND ce.valuenum IS NOT NULL
      -- Limit to the first 72 hours of the ICU stay
      AND ce.charttime BETWEEN hf.intime AND DATETIME_ADD(hf.intime, INTERVAL 72 HOUR)
    GROUP BY
      hf.stay_id,
      chart_hour
  ),
  -- 3. Calculate the 72h composite instability score for each patient in the HF cohort.
  -- The score is the number of hours with at least one unstable vital sign.
  instability_scores AS (
    SELECT
      stay_id,
      COUNTIF(avg_hr > 100 OR avg_map < 65 OR avg_rr > 20) AS instability_score
    FROM
      hourly_vitals_hf
    GROUP BY
      stay_id
  ),
  -- 4. Rank the HF cohort into quartiles based on the instability score.
  ranked_hf_cohort AS (
    SELECT
      stay_id,
      instability_score,
      NTILE(4) OVER (
        ORDER BY
          instability_score DESC
      ) AS instability_quartile
    FROM
      instability_scores
  ),
  -- 5. Calculate comparison metrics (proportions of time, LOS, mortality) for the ENTIRE ICU population
  -- within the first 72 hours of their stay for a fair comparison.
  all_icu_metrics AS (
    WITH
      all_icu_hourly_vitals AS (
        SELECT
          icu.stay_id,
          icu.hadm_id,
          icu.los,
          DATETIME_TRUNC(ce.charttime, HOUR) AS chart_hour,
          AVG(
            CASE WHEN ce.itemid = 220045 THEN ce.valuenum END
          ) AS avg_hr,
          COALESCE(
            AVG(CASE WHEN ce.itemid = 220052 THEN ce.valuenum END),
            AVG(CASE WHEN ce.itemid = 220181 THEN ce.valuenum END)
          ) AS avg_map,
          AVG(
            CASE WHEN ce.itemid = 220210 THEN ce.valuenum END
          ) AS avg_rr
        FROM
          `physionet-data.mimiciv_3_1_icu.icustays` AS icu
          INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON icu.stay_id = ce.stay_id
        WHERE
          ce.itemid IN (220045, 220052, 220181, 220210) AND ce.valuenum IS NOT NULL
          -- Ensure consistent 72-hour window for all patients
          AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
        GROUP BY
          icu.stay_id,
          icu.hadm_id,
          icu.los,
          chart_hour
      )
    SELECT
      v.stay_id,
      v.los,
      adm.hospital_expire_flag,
      -- Calculate the proportion of observed hours spent in each unstable state
      SAFE_DIVIDE(COUNTIF(v.avg_hr > 100), COUNT(v.avg_hr)) AS proportion_tachycardia,
      SAFE_DIVIDE(COUNTIF(v.avg_map < 65), COUNT(v.avg_map)) AS proportion_map_lt_65,
      SAFE_DIVIDE(COUNTIF(v.avg_rr > 20), COUNT(v.avg_rr)) AS proportion_tachypnea
    FROM
      all_icu_hourly_vitals AS v
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON v.hadm_id = adm.hadm_id
    GROUP BY
      v.stay_id,
      v.los,
      adm.hospital_expire_flag
  ),
  -- 6. Pre-calculate aggregate statistics for the two comparison groups for efficiency.
  final_aggregates AS (
    SELECT
      'Unstable Quartile' AS group_name,
      AVG(m.proportion_tachycardia) AS avg_prop_tachy,
      AVG(m.proportion_map_lt_65) AS avg_prop_map,
      AVG(m.proportion_tachypnea) AS avg_prop_rr,
      AVG(m.los) AS avg_los,
      AVG(m.hospital_expire_flag) AS mortality_rate
    FROM all_icu_metrics AS m
    INNER JOIN ranked_hf_cohort AS r ON m.stay_id = r.stay_id
    WHERE
      r.instability_quartile = 1
    UNION ALL
    SELECT
      'Total ICU Population' AS group_name,
      AVG(proportion_tachycardia) AS avg_prop_tachy,
      AVG(proportion_map_lt_65) AS avg_prop_map,
      AVG(proportion_tachypnea) AS avg_prop_rr,
      AVG(los) AS avg_los,
      AVG(hospital_expire_flag) AS mortality_rate
    FROM all_icu_metrics
  )
-- 7. Final SELECT to combine all results into a single, unpivoted output table.
SELECT
  '99th percentile of 72h instability score in HF cohort' AS metric,
  FORMAT('%d', APPROX_QUANTILES(instability_score, 100) [
  OFFSET
    (99)]) AS value
FROM
  instability_scores
UNION ALL
SELECT
  'Average 72h Tachycardia (>100 bpm) Proportion - ' || group_name,
  FORMAT('%.3f', avg_prop_tachy)
FROM final_aggregates
UNION ALL
SELECT
  'Average 72h MAP<65 Proportion - ' || group_name,
  FORMAT('%.3f', avg_prop_map)
FROM final_aggregates
UNION ALL
SELECT
  'Average 72h Tachypnea (>20) Proportion - ' || group_name,
  FORMAT('%.3f', avg_prop_rr)
FROM final_aggregates
UNION ALL
SELECT
  'Average ICU Length of Stay (days) - ' || group_name,
  FORMAT('%.2f', avg_los)
FROM final_aggregates
UNION ALL
SELECT
  'In-Hospital Mortality Rate - ' || group_name,
  FORMAT('%.3f', mortality_rate)
FROM final_aggregates
ORDER BY
  metric;