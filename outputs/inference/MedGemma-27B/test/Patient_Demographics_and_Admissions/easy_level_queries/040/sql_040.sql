WITH RelevantPatients AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 35 AND 45
)
SELECT
  PERCENTILE_CONT(ic.los, 0.5) AS median_los
FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
JOIN RelevantPatients AS rp
  ON ic.subject_id = rp.subject_id;