WITH male_patients_58_68 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 58 AND 68
)

SELECT
  MAX(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS max_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions`
WHERE
  subject_id IN (SELECT subject_id FROM male_patients_58_68)
  AND dischtime IS NOT NULL
  AND admittime IS NOT NULL;