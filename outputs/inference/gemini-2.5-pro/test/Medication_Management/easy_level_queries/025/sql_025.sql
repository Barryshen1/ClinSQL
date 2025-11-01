WITH AmiodaroneDurations AS (
  SELECT
    -- Calculate the duration of each prescription in days
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pr.hadm_id = adm.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON pr.subject_id = p.subject_id
  WHERE
    -- 1. Filter for male patients
    p.gender = 'M'
    -- 2. Filter for patients aged 62-72 at the time of admission
    AND ((EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) + p.anchor_age) BETWEEN 62 AND 72
    -- 3. Filter for amiodarone prescriptions
    AND LOWER(pr.drug) LIKE '%amiodarone%'
    -- 4. Ensure the prescription has a valid, positive duration
    AND pr.stoptime > pr.starttime
)
SELECT
  -- Calculate the Interquartile Range (IQR)
  -- APPROX_QUANTILES with 4 intervals returns an array of 5 values: [min, q1, median, q3, max]
  -- We subtract the 1st quartile (index 1) from the 3rd quartile (index 3)
  (APPROX_QUANTILES(duration_days, 4)[OFFSET(3)]) - (APPROX_QUANTILES(duration_days, 4)[OFFSET(1)]) AS iqr_days
FROM
  AmiodaroneDurations;