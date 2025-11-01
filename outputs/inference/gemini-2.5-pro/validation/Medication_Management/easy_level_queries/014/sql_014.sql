WITH HighIntensityPrescriptions AS (
  SELECT
    -- Calculate the duration in days for each individual prescription order.
    DATETIME_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pres.subject_id = pat.subject_id
  WHERE
    -- 1. Filter for the patient cohort: females aged 86-96
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 86 AND 96
    -- 2. Filter for Atorvastatin, ignoring case and minor name variations
    AND LOWER(pres.drug) LIKE '%atorvastatin%'
    -- 3. Filter for high-intensity dosage (40-80 mg)
    AND LOWER(pres.dose_unit_rx) = 'mg'
    -- Extract the numeric dose, handling text values like '40-80', and check if it's in the 40-80 range.
    AND SAFE_CAST(REGEXP_EXTRACT(pres.dose_val_rx, r'^[0-9\.]+') AS NUMERIC) >= 40
    AND SAFE_CAST(REGEXP_EXTRACT(pres.dose_val_rx, r'^[0-9\.]+') AS NUMERIC) <= 80
    -- 4. Ensure start and stop times are valid for duration calculation
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
    AND pres.stoptime > pres.starttime
)
-- 5. Find the minimum duration from all qualifying prescriptions
SELECT
  MIN(duration_days) AS min_duration_days
FROM
  HighIntensityPrescriptions;