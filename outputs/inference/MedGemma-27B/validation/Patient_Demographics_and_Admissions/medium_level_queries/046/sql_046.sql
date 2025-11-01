WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age BETWEEN 87 AND 97
    AND gender = 'F'
), ICUAdmissions AS (
  SELECT
    p.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    a.dischtime,
    a.deathtime,
    a.discharge_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic ON a.hadm_id = ic.hadm_id
    INNER JOIN PatientInfo AS p ON a.subject_id = p.subject_id
)
SELECT
  discharge_location,
  COUNT(hadm_id) AS n,
  AVG(los) AS mean_los,
  STDDEV(los) AS sd_los,
  SUM(CASE WHEN los < 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(hadm_id) AS percent_los_less_than_10_days
FROM
  ICUAdmissions
GROUP BY
  discharge_location
ORDER BY
  discharge_location;