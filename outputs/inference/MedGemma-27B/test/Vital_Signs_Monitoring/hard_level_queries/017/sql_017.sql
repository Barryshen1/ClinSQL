WITH AsthmaPatients AS (
  -- Identify ICU patients with asthma exacerbation
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    p.gender,
    p.anchor_age,
    di.icd_code,
    di.icd_version
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ic.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON ic.hadm_id = di.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND di.icd_code LIKE 'J45.9%' -- Asthma exacerbation, unspecified severity
    AND ic.stay_id IS NOT NULL
    AND ic.intime IS NOT NULL
    AND ic.outtime IS NOT NULL
),
InstabilityScore AS (
  -- Calculate the instability score for each hour
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ce.charttime,
    -- Calculate the instability score based on the provided formula
    (
      CASE
        WHEN ce.itemid = 50912 THEN 1 -- Heart Rate
        WHEN ce.itemid = 6150 THEN 1 -- Respiratory Rate
        WHEN ce.itemid = 44818 THEN 1 -- Systolic Blood Pressure
        WHEN ce.itemid = 4583 THEN 1 -- Diastolic Blood Pressure
        WHEN ce.itemid = 44819 THEN 1 -- Mean Arterial Pressure
        WHEN ce.itemid = 220179 THEN 1 -- Oxygen Saturation
        ELSE 0
      END
    ) AS score
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON ce.stay_id = ic.stay_id
  WHERE
    ce.itemid IN (50912, 6150, 44818, 4583, 44819, 220179)
    AND ce.charttime IS NOT NULL
),
InstabilityScoreFirst72h AS (
  -- Filter the instability score for the first 72 hours
  SELECT
    is.subject_id,
    is.hadm_id,
    is.stay_id,
    is.charttime,
    is.score
  FROM
    InstabilityScore AS is
  JOIN
    AsthmaPatients AS ap
    ON is.subject_id = ap.subject_id
    AND is.hadm_id = ap.hadm_id
    AND is.stay_id = ap.stay_id
  WHERE
    is.charttime BETWEEN ap.intime AND TIMESTAMP_ADD(ap.intime, INTERVAL 72 HOUR)
),
InstabilityScoreSummary AS (
  -- Calculate the summary statistics for the instability score
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    AVG(score) AS avg_score,
    STDDEV(score) AS stddev_score,
    PERCENTILE_CONT(score, 0.25) AS p25_score,
    PERCENTILE_CONT(score, 0.50) AS p50_score,
    PERCENTILE_CONT(score, 0.75) AS p75_score,
    PERCENTILE_CONT(score, 0.95) AS p95_score
  FROM
    InstabilityScoreFirst72h
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
),
AgeMatchedCohort AS (
  -- Identify the age-matched cohort
  SELECT
    p.subject_id,
    p.hadm_id,;