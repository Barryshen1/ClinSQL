WITH NitratePrescriptionDurations AS (
  SELECT
    -- Calculate the duration in fractional days for higher precision.
    TIMESTAMP_DIFF(rx.stoptime, rx.starttime, HOUR) / 24.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON rx.subject_id = pat.subject_id
  WHERE
    -- 1. Filter for the specified patient cohort: female, aged 73-83.
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 73 AND 83
    -- 2. Filter for nitrate medications using common drug names.
    AND (
      LOWER(rx.drug) LIKE '%nitroglycerin%'
      OR LOWER(rx.drug) LIKE '%isosorbide%'
      OR LOWER(rx.drug) LIKE '%nitroprusside%' -- Common IV nitrate
      OR LOWER(rx.drug) LIKE '%nitrate%'     -- General catch-all
    )
    -- 3. Ensure valid start and stop times exist to calculate a positive duration.
    AND rx.starttime IS NOT NULL
    AND rx.stoptime IS NOT NULL
    AND rx.starttime < rx.stoptime
)
-- 4. Calculate the standard deviation of all calculated prescription durations.
SELECT
  STDDEV(nitrate.duration_days) AS sd_nitrate_duration_days
FROM
  NitratePrescriptionDurations AS nitrate;