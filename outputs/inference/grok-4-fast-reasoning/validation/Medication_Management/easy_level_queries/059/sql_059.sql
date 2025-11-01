WITH arb_prescriptions AS (
  SELECT
    TIMESTAMP_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
  ON
    a.subject_id = pres.subject_id
    AND a.hadm_id = pres.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
    AND pres.starttime >= a.admittime
    AND pres.stoptime IS NOT NULL
    AND pres.starttime < pres.stoptime
    AND pres.stoptime <= a.dischtime
    AND (
      LOWER(pres.drug) LIKE '%losartan%'
      OR LOWER(pres.drug) LIKE '%valsartan%'
      OR LOWER(pres.drug) LIKE '%irbesartan%'
      OR LOWER(pres.drug) LIKE '%candesartan%'
      OR LOWER(pres.drug) LIKE '%telmisartan%'
      OR LOWER(pres.drug) LIKE '%olmesartan%'
      OR LOWER(pres.drug) LIKE '%azilsartan%'
      OR LOWER(pres.drug) LIKE '%eprosartan%'
    )
)

SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] AS p75_duration_days
FROM
  arb_prescriptions
WHERE
  duration_days > 0;