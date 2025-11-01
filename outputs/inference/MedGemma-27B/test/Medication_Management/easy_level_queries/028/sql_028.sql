WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 49
),
AdmissionsInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN PatientInfo AS p
    ON a.subject_id = p.subject_id
),
PrescriptionInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.starttime,
    p.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN AdmissionsInfo AS a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE
    p.drug LIKE '%aspirin%' OR p.drug LIKE '%clopidogrel%' OR p.drug LIKE '%ticagrelor%' OR p.drug LIKE '%prasugrel%'
),
DAPT_Patients AS (
  SELECT
    subject_id,
    hadm_id
  FROM PrescriptionInfo
  GROUP BY
    subject_id,
    hadm_id
  HAVING
    COUNT(DISTINCT drug) >= 2
),
PrescriptionDuration AS (
  SELECT
    dp.subject_id,
    dp.hadm_id,
    dp.drug,
    dp.starttime,
    dp.stoptime,
    TIMESTAMP_DIFF(dp.stoptime, dp.starttime, DAY) AS duration_days
  FROM PrescriptionInfo AS dp
  JOIN DAPT_Patients AS dapt
    ON dp.subject_id = dapt.subject_id AND dp.hadm_id = dapt.hadm_id
  WHERE
    dp.drug LIKE '%aspirin%' OR dp.drug LIKE '%clopidogrel%' OR dp.drug LIKE '%ticagrelor%' OR dp.drug LIKE '%prasugrel%'
)
SELECT
  STDDEV(duration_days)
FROM PrescriptionDuration;