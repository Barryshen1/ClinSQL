WITH female_patients_80_90 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 80 AND 90
),

nitrate_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.pharmacy_id,
    p.drug,
    p.route,
    p.starttime,
    p.stoptime,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, HOUR) AS duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    female_patients_80_90 fp ON p.subject_id = fp.subject_id
  WHERE
    (LOWER(p.drug) LIKE '%nitrate%'
     OR LOWER(p.drug_type) LIKE '%nitrate%')
    AND (LOWER(p.route) IN ('iv', 'oral', 'sublingual'))
    AND p.stoptime IS NOT NULL  -- Exclude ongoing prescriptions
)

SELECT
  MAX(duration_hours) AS max_duration_hours
FROM
  nitrate_prescriptions;