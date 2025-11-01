WITH PatientAge AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime, -- Corrected column name
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 57 AND 67
),
LOSCalculation AS (
  SELECT
    hadm_id,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'HOME' THEN 'Discharged home'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
      ELSE 'Other'
    END AS discharge_disposition,
    CASE
      WHEN hospital_expire_flag = 1 THEN TIMESTAMP_DIFF(dischtime, admitime, DAY) -- Corrected column name
      ELSE TIMESTAMP_DIFF(dischtime, admitime, DAY) -- Corrected column name
    END AS los
  FROM
    PatientAge
  WHERE
    admission_type = 'EMERGENCY'
)
SELECT
  discharge_disposition,
  AVG(los) AS mean_los,
  MEDIAN(los) AS median_los,
  PERCENTILE_CONT(los, 0.75) AS p75_los,
  PERCENTILE_CONT(los, 0.90) AS p90_los,
  PERCENTILE_CONT(los, 0.10) AS p10_los
FROM
  LOSCalculation
GROUP BY
  discharge_disposition;