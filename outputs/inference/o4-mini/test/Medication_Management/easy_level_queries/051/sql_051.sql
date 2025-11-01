WITH target_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
),
digoxin_prescriptions AS (
  SELECT
    tp.subject_id,
    tp.hadm_id,
    pres.starttime,
    pres.stoptime,
    -- Compute duration in days as an integer
    DATE_DIFF(DATE(pres.stoptime), DATE(pres.starttime), DAY) AS duration_days
  FROM
    target_patients AS tp
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
      USING(subject_id, hadm_id)
  WHERE
    pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
    AND pres.stoptime > pres.starttime
    AND LOWER(pres.drug) LIKE '%digoxin%'
),
quartiles AS (
  SELECT
    -- APPROX_QUANTILES on an INT64 is supported
    APPROX_QUANTILES(duration_days, 4) AS q_array
  FROM
    digoxin_prescriptions
)
SELECT
  q_array[OFFSET(1)] AS q1_duration_days,
  q_array[OFFSET(3)] AS q3_duration_days
FROM
  quartiles;