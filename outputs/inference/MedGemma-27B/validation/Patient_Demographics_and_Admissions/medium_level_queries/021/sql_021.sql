WITH PatientDemographics AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    a.admission_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 67 AND 77 AND a.admission_type = 'SURG'
),
LOSCalculation AS (
  SELECT
    subject_id,
    TIMESTAMP_DIFF(dischtime, admitime, DAY) AS los_days,
    discharge_location
  FROM
    PatientDemographics
)
SELECT
  discharge_location,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS sd_los,
  COUNT(CASE WHEN los_days <= 7 THEN 1 ELSE NULL END) * 100.0 / COUNT(subject_id) AS percent_los_le_7_days
FROM
  LOSCalculation
GROUP BY
  discharge_location;