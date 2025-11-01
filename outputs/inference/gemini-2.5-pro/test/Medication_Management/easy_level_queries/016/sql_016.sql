WITH ValidNitratePrescriptions AS (
  -- Step 1: Identify male patients aged 76-86 and their relevant nitrate prescriptions.
  SELECT
    pres.subject_id,
    pres.hadm_id,
    -- Step 2: Calculate the duration of each prescription in days.
    DATETIME_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
    ON pat.subject_id = pres.subject_id
  WHERE
    -- Filter for the patient cohort: males aged 76-86.
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 76 AND 86
    -- Filter for nitrate drugs using common names.
    AND (
      LOWER(pres.drug) LIKE '%nitroglycerin%'
      OR LOWER(pres.drug) LIKE '%isosorbide%'
      OR LOWER(pres.drug) LIKE '%nitrate%'
    )
    -- Filter for oral (PO) or intravenous (IV) routes.
    AND pres.route IN ('PO', 'IV')
    -- Ensure valid start and stop times exist for duration calculation.
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
    -- Ensure the calculated duration is not negative.
    AND pres.stoptime >= pres.starttime
)
-- Step 3: Calculate the 25th percentile of the collected durations.
SELECT DISTINCT
  PERCENTILE_CONT(duration_days, 0.25) OVER() AS p25_duration_days
FROM
  ValidNitratePrescriptions;