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
    -- This is a placeholder, the actual instability score calculation needs to be defined.
    -- For demonstration, let's assume a simple score based on some parameters.
    -- Replace this with the actual instability score calculation based on clinical criteria.
    85 AS instability_score
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  WHERE
    ic.mortality = 1 -- Filter for mortality
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
    is.hadm_id,
    is.stay_id,
    is.intime,
    is.outtime,
    is.los,
    is.mortality,
    is.instability_score
  FROM
    InstabilityScore AS is
  JOIN
    PatientDemographics AS pd
    ON is.subject_id = pd.subject_id
  WHERE
    pd.gender = 'M' AND pd.anchor_age BETWEEN 88 AND 98
    -- Filter for patients within the first 72 hours of ICU admission
    AND is.intime BETWEEN TIMESTAMP_SUB(is.intime, INTERVAL 72 HOUR) AND is.intime
)
SELECT
  -- Calculate the percentile of the instability score
  PERCENTILE_CONT(instability_score, 0.5) OVER (PARTITION BY hadm_id) AS median_instability_score_percentile,
  -- Calculate the average ICU LOS for the most unstable quartile
  AVG(los) AS avg_icu_los_most_unstable_quartile,
  -- Calculate the hospital mortality rate for the most unstable quartile
  AVG(mortality) AS hospital_mortality_most_unstable_quartile
FROM
  CombinedData
WHERE
  instability_score >= PERCENTILE_CONT(instability_score, 0.75) OVER (PARTITION BY hadm_id)
GROUP BY
  hadm_id;