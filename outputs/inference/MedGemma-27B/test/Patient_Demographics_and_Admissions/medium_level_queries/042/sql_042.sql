WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admission_type,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'PHYSICIAN REFERRAL'
)
SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
    WHEN hospital_expire_flag = 0 THEN 'Discharged alive'
    ELSE NULL
  END AS outcome,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY) + 1) AS mean_los,
  APPROX_QUANTILES(TIMESTAMP_DIFF(dischtime, admittime, DAY) + 1, [0.5, 0.75, 0.90, 0.05]) AS quantiles
FROM PatientInfo
GROUP BY
  outcome
ORDER BY
  outcome;