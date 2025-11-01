WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 76 AND 86
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.hadm_id IN (
      SELECT
        DISTINCT hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.emar`
      WHERE
        medication LIKE '%aspirin%' OR medication LIKE '%clopidogrel%' OR medication LIKE '%ticagrelor%' OR medication LIKE '%prasugrel%'
    )
), ICUStayInfo AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  WHERE
    ic.hadm_id IN (
      SELECT
        hadm_id
      FROM
        AdmissionInfo
    )
)
SELECT
  AVG(CAST(EXTRACT(EPOCH FROM (ic.outtime - ic.intime)) AS NUMERIC) / 86400) AS average_icu_los_days
FROM
  ICUStayInfo AS ic;