WITH digoxin_prescriptions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    pres.starttime,
    pres.stoptime,
    TIMESTAMP_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON a.hadm_id = pres.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND LOWER(pres.drug) = 'digoxin'
    AND pres.stoptime IS NOT NULL
)

SELECT
  MAX(duration_days) AS longest_digoxin_prescription_duration_days
FROM
  digoxin_prescriptions;