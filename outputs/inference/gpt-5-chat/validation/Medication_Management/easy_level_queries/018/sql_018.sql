WITH male_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    -- compute age at admission
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS admit_age,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
digoxin_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
)
SELECT
  MAX(dp.duration_days) AS max_digoxin_duration_days
FROM male_patients mp
JOIN digoxin_prescriptions dp
  ON mp.subject_id = dp.subject_id
  AND mp.hadm_id = dp.hadm_id
WHERE mp.admit_age BETWEEN 82 AND 92;