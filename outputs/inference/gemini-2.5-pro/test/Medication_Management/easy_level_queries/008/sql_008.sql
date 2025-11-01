WITH
-- Step 1: Identify the target patient demographic (men aged 64-74)
patient_cohort AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
),

-- Step 2: Find all inpatient prescriptions for Aspirin or P2Y12 inhibitors
antiplatelet_prescriptions AS (
  SELECT
    px.subject_id,
    px.hadm_id,
    px.starttime,
    px.stoptime,
    -- Flag for Aspirin
    CASE
      WHEN LOWER(px.drug) LIKE '%aspirin%'
      THEN 1
      ELSE 0
    END AS is_aspirin,
    -- Flag for P2Y12 inhibitors (Clopidogrel, Ticagrelor, Prasugrel)
    CASE
      WHEN LOWER(px.drug) LIKE '%clopidogrel%'
        OR LOWER(px.drug) LIKE '%ticagrelor%'
        OR LOWER(px.drug) LIKE '%prasugrel%'
      THEN 1
      ELSE 0
    END AS is_p2y12
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS px
  WHERE
    -- Filter for relevant drugs
    (
      LOWER(px.drug) LIKE '%aspirin%'
      OR LOWER(px.drug) LIKE '%clopidogrel%'
      OR LOWER(px.drug) LIKE '%ticagrelor%'
      OR LOWER(px.drug) LIKE '%prasugrel%'
    )
    -- Ensure prescription has a valid duration
    AND px.starttime IS NOT NULL AND px.stoptime IS NOT NULL
),

-- Step 3: For each admission, calculate the total duration of antiplatelet therapy
-- and filter for admissions that received both drug types.
admission_durations AS (
  SELECT
    ap.hadm_id,
    -- Calculate duration as the time from the first antiplatelet start to the last antiplatelet stop
    DATETIME_DIFF(MAX(ap.stoptime), MIN(ap.starttime), DAY) AS antiplatelet_duration_days
  FROM
    antiplatelet_prescriptions AS ap
  INNER JOIN
    patient_cohort AS pc
    ON ap.subject_id = pc.subject_id
  GROUP BY
    ap.hadm_id
  HAVING
    -- Ensure the admission included at least one prescription for Aspirin AND one for a P2Y12 inhibitor
    MAX(ap.is_aspirin) = 1 AND MAX(ap.is_p2y12) = 1
)

-- Final Step: Calculate the median duration across all qualifying admissions
SELECT
  APPROX_QUANTILES(ad.antiplatelet_duration_days, 100)[OFFSET(50)] AS median_inpatient_antiplatelet_duration_days
FROM
  admission_durations AS ad
WHERE
  -- Ensure calculated duration is non-negative
  ad.antiplatelet_duration_days >= 0;