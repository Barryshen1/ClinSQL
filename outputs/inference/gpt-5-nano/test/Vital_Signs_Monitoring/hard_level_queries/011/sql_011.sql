WITH pneumonia_cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.los AS icu_los,
    a.hospital_expire_flag AS mortality,
    -- Instability score over first 24h: sum of abnormal vital-sign observations
    (
      -- Heart Rate > 100
      IFNULL(
        (
          SELECT SUM(1)
          FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
          JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di ON di.itemid = ce.itemid
          WHERE ce.subject_id = i.subject_id
            AND ce.hadm_id = i.hadm_id
            AND ce.stay_id = i.stay_id
            AND ce.charttime >= i.intime
            AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
            AND (di.label LIKE '%Heart Rate%' OR di.label LIKE '%Heart rate%')
            AND ce.valuenum IS NOT NULL
            AND ce.valuenum > 100
        ),
        0
      )
      +
      -- Systolic BP extremes
      IFNULL(
        (
          SELECT SUM(1)
          FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
          JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di ON di.itemid = ce.itemid
          WHERE ce.subject_id = i.subject_id
            AND ce.hadm_id = i.hadm_id
            AND ce.stay_id = i.stay_id
            AND ce.charttime >= i.intime
            AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
            AND (di.label LIKE '%Systolic Blood Pressure%' OR di.label LIKE '%Systolic BP%' OR di.label LIKE '%Blood Pressure%')
            AND ce.valuenum IS NOT NULL
            AND (ce.valuenum < 90 OR ce.valuenum > 180)
        ),
        0
      )
      +
      -- Respiratory Rate
      IFNULL(
        (
          SELECT SUM(1)
          FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
          JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di ON di.itemid = ce.itemid
          WHERE ce.subject_id = i.subject_id
            AND ce.hadm_id = i.hadm_id
            AND ce.stay_id = i.stay_id
            AND ce.charttime >= i.intime
            AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
            AND (di.label LIKE '%Respiratory Rate%' OR di.label LIKE '%Resp Rate%')
            AND ce.valuenum IS NOT NULL
            AND ce.valuenum > 24
        ),
        0
      )
      +
      -- Temperature
      IFNULL(
        (
          SELECT SUM(1)
          FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
          JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di ON di.itemid = ce.itemid
          WHERE ce.subject_id = i.subject_id
            AND ce.hadm_id = i.hadm_id
            AND ce.stay_id = i.stay_id
            AND ce.charttime >= i.intime
            AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
            AND (di.label LIKE '%Temperature%' OR di.label LIKE '%Temp%')
            AND ce.valuenum IS NOT NULL
            AND (ce.valuenum > 38 OR ce.valuenum < 36)
        ),
        0
      )
    ) AS instability_score_24h
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON p.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di ON di.subject_id = i.subject_id AND di.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 55 AND 65
    AND LOWER(d.long_title) LIKE '%pneumonia%'
)

, decile AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    icu_los,
    mortality,
    instability_score_24h,
    NTILE(10) OVER (ORDER BY instability_score_24h DESC) AS decile
  FROM pneumonia_cohort
)

, summary AS (
  SELECT decile, AVG(icu_los) AS mean_icu_los, AVG(mortality) AS mortality_rate
  FROM decile
  GROUP BY decile
)

, percentile_60 AS (
  SELECT
    100 * SAFE_DIVIDE(
      SUM(CASE WHEN instability_score_24h <= 60 THEN 1 ELSE 0 END),
      COUNT(*) ) AS percentile_60
  FROM pneumonia_cohort
)

SELECT
  percentile_60.percentile_60 AS percentile_60,
  (SELECT mean_icu_los FROM summary WHERE decile = 1) AS mean_icu_los_most_unstable_decile,
  (SELECT mortality_rate FROM summary WHERE decile = 1) AS mortality_rate_most_unstable_decile
FROM percentile_60;