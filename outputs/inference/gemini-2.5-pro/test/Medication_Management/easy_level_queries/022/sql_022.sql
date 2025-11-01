WITH PrescriptionDurations AS (
  SELECT
    -- Calculate the duration of each prescription in hours
    DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) AS duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pa
    ON pr.subject_id = pa.subject_id
  WHERE
    -- Filter for the patient cohort: women aged 59-69
    pa.gender = 'F'
    AND pa.anchor_age BETWEEN 59 AND 69
    -- Filter for inpatient prescriptions, excluding discharge meds
    AND pr.drug_type != 'DISCHARGE'
    -- Ensure start and stop times are present to calculate duration
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    -- Identify dihydropyridine CCBs by name
    AND (
      LOWER(pr.drug) LIKE '%amlodipine%'
      OR LOWER(pr.drug) LIKE '%nifedipine%'
      OR LOWER(pr.drug) LIKE '%felodipine%'
      OR LOWER(pr.drug) LIKE '%nicardipine%'
      OR LOWER(pr.drug) LIKE '%nimodipine%'
      OR LOWER(pr.drug) LIKE '%isradipine%'
      OR LOWER(pr.drug) LIKE '%clevidipine%'
    )
)
-- Calculate the median from the calculated durations
SELECT
  APPROX_QUANTILES(duration_hours, 2)[OFFSET(1)] AS median_prescription_duration_hours
FROM
  PrescriptionDurations
WHERE
  -- Ensure only positive, valid durations are included in the median calculation
  duration_hours > 0;