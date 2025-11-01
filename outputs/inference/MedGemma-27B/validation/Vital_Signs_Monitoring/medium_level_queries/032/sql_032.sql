WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.anchor_age = 58
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.discharge_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
), ICUStayInfo AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.careunit
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  WHERE
    s.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
    AND s.careunit IN ('STEPDOWN', 'IMC')
), VentilationInfo AS (
  SELECT
    DISTINCT
    i.subject_id,
    i.hadm_id,
    i.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS i
  WHERE
    i.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
    AND i.itemid = 50613 -- Invasive mechanical ventilation
    AND i.value = 'Yes'
), SBPInfo AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS sbp_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  WHERE
    c.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
    AND c.itemid = 220179 -- Systolic blood pressure
    AND c.valuenum IS NOT NULL
)
SELECT
  STDDEV(sbp_value)
FROM
  SBPInfo AS sbp
WHERE
  sbp.subject_id IN (
    SELECT
      subject_id
    FROM
      PatientInfo
  )
  AND sbp.hadm_id IN (
    SELECT
      hadm_id
    FROM
      AdmissionInfo
  )
  AND sbp.stay_id IN (
    SELECT
      stay_id
    FROM
      ICUStayInfo
  )
  AND sbp.stay_id IN (
    SELECT
      stay_id
    FROM
      VentilationInfo
  )
  AND EXTRACT(HOUR FROM sbp.charttime) BETWEEN 0 AND 5;