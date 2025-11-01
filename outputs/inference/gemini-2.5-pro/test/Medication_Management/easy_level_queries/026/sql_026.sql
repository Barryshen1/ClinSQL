WITH PrescriptionDurations AS (
  -- First, select the duration in days for each relevant prescription
  SELECT
    DATETIME_DIFF(presc.stoptime, presc.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS presc
    ON pat.subject_id = presc.subject_id
  WHERE
    -- Filter for the patient cohort: women aged 81-91
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
    -- Filter for dihydropyridine calcium channel blockers using a regular expression
    -- This covers common drugs like Amlodipine, Nifedipine, Nicardipine, etc.
    AND REGEXP_CONTAINS(LOWER(presc.drug), r'amlodipine|nifedipine|nicardipine|felodipine|isradipine|nisoldipine|clevidipine')
    -- Ensure start and stop times are available to calculate duration
    AND presc.starttime IS NOT NULL
    AND presc.stoptime IS NOT NULL
    -- Ensure the duration is non-negative
    AND presc.stoptime >= presc.starttime
)
-- Then, calculate the 25th percentile of these durations
SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS percentile_25_duration_days
FROM
  PrescriptionDurations;