WITH ValidPrescriptions AS (
  SELECT
    -- Calculate the duration of the prescription in days
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON p.subject_id = pr.subject_id
  WHERE
    -- 1. Filter for the patient cohort: female, aged 60-70
    p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70
    -- 2. Filter for the specific medication
    AND LOWER(pr.drug) LIKE '%atorvastatin%'
    -- 3. Filter for the specific dose and unit
    AND LOWER(pr.dose_unit_rx) = 'mg'
    AND SAFE_CAST(REGEXP_EXTRACT(pr.dose_val_rx, r'^\d+\.?\d*') AS NUMERIC) BETWEEN 40 AND 80
    -- 4. Ensure the prescription has a valid start and stop time to calculate duration
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    -- 5. Ensure the duration is non-negative
    AND DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) >= 0
)
-- Calculate the Interquartile Range (IQR) from the collected durations
SELECT
  -- APPROX_QUANTILES with 4 buckets returns [min, 25th_percentile, 50th_percentile, 75th_percentile, max]
  -- IQR = 75th percentile (offset 3) - 25th percentile (offset 1)
  (APPROX_QUANTILES(duration_days, 4)[OFFSET(3)]) - (APPROX_QUANTILES(duration_days, 4)[OFFSET(1)]) AS iqr_prescription_days
FROM
  ValidPrescriptions;