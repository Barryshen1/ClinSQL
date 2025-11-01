WITH female_patients_81_91 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 81 AND 91
),

ccb_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.pharmacy_id,
    p.drug,
    p.starttime,
    p.stoptime,
    TIMESTAMP_DIFF(
      IFNULL(p.stoptime, CURRENT_DATETIME()),
      p.starttime,
      DAY
    ) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    female_patients_81_91 fp ON p.subject_id = fp.subject_id
  WHERE
    p.drug IN (
      'Amlodipine', 'Nifedipine', 'Felodipine', 'Nicardipine',
      'Nisoldipine', 'Isradipine', 'Clevidipine'
    )
    AND p.stoptime IS NOT NULL
    AND TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) > 0
)

SELECT
  PERCENTILE_CONT(duration_days, 0.25) OVER() AS p25_duration_days
FROM
  ccb_prescriptions
LIMIT 1;