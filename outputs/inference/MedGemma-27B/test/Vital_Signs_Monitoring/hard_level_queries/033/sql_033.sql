WITH InstabilityScore AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    ic.mortality,
    -- Calculate instability score (example calculation, replace with actual score logic)
    -- This is a placeholder, the actual instability score calculation is complex and depends on specific criteria.
    -- For demonstration, we'll use a simplified score based on heart rate and respiratory rate.
    -- Assume heart rate itemid = 211, respiratory rate itemid = 442
    -- Note: This is a simplified example and may not reflect a real instability score.
    (
      COALESCE(
        (
          SELECT
            valuenum
          FROM
            `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
          WHERE
            ce.subject_id = ic.subject_id
            AND ce.hadm_id = ic.hadm_id
            AND ce.stay_id = ic.stay_id
            AND ce.itemid = 211 -- Heart Rate
            AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
          ORDER BY
            ce.charttime DESC
          LIMIT 1
        ), 0) + COALESCE(
        (
          SELECT
            valuenum
          FROM
            `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
          WHERE
            ce.subject_id = ic.subject_id
            AND ce.hadm_id = ic.hadm_id
            AND ce.stay_id = ic.stay_id
            AND ce.itemid = 442 -- Respiratory Rate
            AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
          ORDER BY
            ce.charttime DESC
          LIMIT 1
        ), 0)
    ) AS instability_score
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  WHERE
    ic.first_careunit LIKE '%ICU%'
    AND ic.los > 0
),
PatientDemographics AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
),
CombinedData AS (
  SELECT
    pd.subject_id,
    pd.gender,
    pd.anchor_age,
    iscore.hadm_id,
    iscore.stay_id,
    iscore.intime,
    iscore.outtime,
    iscore.los,
    iscore.mortality,
    iscore.instability_score
  FROM
    InstabilityScore AS iscore
  JOIN
    PatientDemographics AS pd
    ON iscore.subject_id = pd.subject_id
  WHERE
    pd.gender = 'F'
    AND pd.anchor_age BETWEEN 51 AND 61
    AND iscore.instability_score IS NOT NULL
)
SELECT
  -- Calculate percentile for instability score of 80
  PERCENTILE_CONT(instability_score, 0.80) AS percentile_80,
  -- Calculate ICU LOS and mortality for the most unstable decile (top 10%)
  AVG(los) AS avg_los_top_decile,
  AVG(mortality) AS avg_mortality_top_decile
FROM
  CombinedData
WHERE
  instability_score >= PERCENTILE_CONT(instability_score, 0.90);