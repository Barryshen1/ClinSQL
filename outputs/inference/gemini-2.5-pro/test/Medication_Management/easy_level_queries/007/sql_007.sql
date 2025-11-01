WITH prescription_durations AS (
  SELECT
    -- Calculate the duration of each prescription in days
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON p.subject_id = pr.subject_id
  WHERE
    -- 1. Filter for female patients aged 90-100
    p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
    -- 2. Filter for thiazide-like diuretics by generic name
    AND (
      LOWER(pr.drug) LIKE '%chlorthalidone%'
      OR LOWER(pr.drug) LIKE '%indapamide%'
      OR LOWER(pr.drug) LIKE '%metolazone%'
    )
    -- 3. Ensure valid start and stop times for duration calculation
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime
)
-- 4. Calculate the Interquartile Range (IQR) from the collected durations
SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] - APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS iqr_prescription_duration_days
FROM
  prescription_durations
WHERE
  -- Ensure we are calculating on valid, non-negative durations
  duration_days >= 0;