WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 69
    AND gender = 'M'
),
AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
),
ICUInfo AS (
  SELECT
    i.hadm_id,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  INNER JOIN
    AdmissionInfo AS a
    ON i.hadm_id = a.hadm_id
),
CombinedInfo AS (
  SELECT
    a.hadm_id,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    i.los
  FROM
    AdmissionInfo AS a
  LEFT JOIN
    ICUInfo AS i
    ON a.hadm_id = i.hadm_id
),
GroupedInfo AS (
  SELECT
    hadm_id,
    dischtime,
    discharge_location,
    hospital_expire_flag,
    los,
    CASE
      WHEN hospital_expire_flag = 1
      THEN 'in-hospital death'
      WHEN discharge_location IN ('HOME', 'SNF', 'LTACH')
      THEN 'home; SNF/rehab/LTACH'
      ELSE 'other'
    END AS discharge_category
  FROM
    CombinedInfo
)
SELECT
  discharge_category,
  COUNT(hadm_id) AS count,
  SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(hadm_id) AS proportion_los_ge_7_days,
  PERCENTILE_CONT(los, 0.14) AS percentile_14_day
FROM
  GroupedInfo
GROUP BY
  discharge_category;