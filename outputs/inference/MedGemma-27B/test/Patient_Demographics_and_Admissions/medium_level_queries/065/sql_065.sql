WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    a.admission_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
), CombinedInfo AS (
  SELECT
    pi.subject_id,
    pi.gender,
    pi.anchor_age,
    ai.hadm_id,
    ai.admittime,
    ai.dischtime,
    ai.deathtime,
    ai.discharge_location,
    ai.admission_location
  FROM
    PatientInfo AS pi
  INNER JOIN
    AdmissionInfo AS ai
    ON pi.subject_id = ai.subject_id
)
SELECT
  CASE
    WHEN ci.deathtime IS NOT NULL
    THEN 'In-Hospital Mortality'
    WHEN ci.discharge_location = 'HOME'
    THEN 'Discharged Home'
    WHEN ci.discharge_location = 'HOSPICE'
    THEN 'Discharged to Hospice'
    ELSE 'Other'
  END AS discharge_status,
  AVG(TIMESTAMP_DIFF(ci.dischtime, ci.admittime, DAY)) AS mean_los_days,
  STDDEV(TIMESTAMP_DIFF(ci.dischtime, ci.admittime, DAY)) AS sd_los_days
FROM
  CombinedInfo AS ci
WHERE
  ci.gender = 'F'
  AND ci.anchor_age BETWEEN 75 AND 85
  AND ci.admission_location = 'WARD'
  AND ci.hadm_id NOT IN (
    SELECT
      DISTINCT
      i.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS i
  )
GROUP BY
  discharge_status
ORDER BY
  discharge_status;