WITH relevant_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.drug LIKE 'spironolactone'
    OR p.drug LIKE 'eplerenone'
),
filtered_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
combined_data AS (
  SELECT
    rp.subject_id,
    rp.hadm_id,
    rp.starttime,
    rp.stoptime,
    fp.gender,
    fp.anchor_age
  FROM
    relevant_prescriptions AS rp
  INNER JOIN
    filtered_patients AS fp
    ON rp.subject_id = fp.subject_id
)
SELECT
  PERCENTILE_CONT(0.5, TIMESTAMP_DIFF(stoptime, starttime, DAY)) AS median_duration_days
FROM
  combined_data;