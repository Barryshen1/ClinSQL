WITH
  -- Step 1: Define the patient cohort (males aged 57-67)
  PatientCohort AS (
    SELECT
      subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'M'
      AND anchor_age BETWEEN 57 AND 67
  ),

  -- Step 2: Classify all relevant antiplatelet prescriptions
  AntiplateletPrescriptions AS (
    SELECT
      p.subject_id,
      p.hadm_id,
      p.starttime,
      p.stoptime,
      CASE
        WHEN LOWER(p.drug) LIKE '%aspirin%'
        THEN 'aspirin'
        WHEN
          LOWER(p.drug) LIKE '%clopidogrel%'
          OR LOWER(p.drug) LIKE '%ticagrelor%'
          OR LOWER(p.drug) LIKE '%prasugrel%'
        THEN 'p2y12_inhibitor'
        ELSE NULL
      END AS drug_class
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    WHERE
      -- Ensure timestamps are available for duration calculation
      p.starttime IS NOT NULL
      AND p.stoptime IS NOT NULL
  ),

  -- Step 3: Identify DAPT admissions and calculate the duration of therapy for each
  DaptDurations AS (
    SELECT
      ap.hadm_id,
      -- Calculate duration from the earliest start to the latest stop time of any DAPT drug
      DATETIME_DIFF(MAX(ap.stoptime), MIN(ap.starttime), DAY) AS dapt_duration_days
    FROM
      AntiplateletPrescriptions AS ap
      -- Join with the patient cohort to filter for the correct population
    INNER JOIN
      PatientCohort AS pc
      ON ap.subject_id = pc.subject_id
    WHERE
      ap.drug_class IS NOT NULL
    GROUP BY
      ap.hadm_id
    -- This HAVING clause is key: it ensures the admission had BOTH drug classes
    HAVING
      COUNT(DISTINCT ap.drug_class) = 2
  )

-- Step 4: Calculate the Interquartile Range (IQR) of the DAPT durations
SELECT
  -- IQR = 75th percentile (Q3) - 25th percentile (Q1)
  (
    APPROX_QUANTILES(dapt_duration_days, 4)[OFFSET(3)]
    - APPROX_QUANTILES(dapt_duration_days, 4)[OFFSET(1)]
  ) AS iqr_dapt_duration_days
FROM
  DaptDurations
-- Add a sanity check for non-negative durations
WHERE
  dapt_duration_days >= 0;