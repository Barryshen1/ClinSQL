WITH PatientCohort AS (
  -- Select subject_ids of male patients aged 43-53
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 43 AND 53
),
PrescriptionDurations AS (
  -- Calculate the duration of each warfarin prescription for the cohort
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.drug = 'warfarin',
    pr.starttime,
    pr.stoptime,
    -- Calculate duration in days
    (TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) + 1) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  WHERE
    pr.drug = 'warfarin' AND pr.subject_id IN (SELECT subject_id FROM PatientCohort)
    AND pr.stoptime IS NOT NULL -- Only consider prescriptions with a stop time
),
AverageDuration AS (
  -- Calculate the average duration
  SELECT
    AVG(duration_days) AS average_duration_days
  FROM
    PrescriptionDurations
)
-- Final result
SELECT
  average_duration_days
FROM
  AverageDuration;