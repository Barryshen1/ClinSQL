WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    gender = 'M' AND anchor_age = 81
),
AdmissionsInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    )
),
ICUStaysInfo AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    s.last_careunit
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  WHERE
    s.subject_id IN (
      SELECT
        subject_id
      FROM AdmissionsInfo
      WHERE
        admission_location = 'EMERGENCY ROOM'
    )
    AND s.last_careunit IN ('STEPDOWN UNIT', 'INTERMEDIATE CARE UNIT')
),
SBPMeasurements AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  WHERE
    c.itemid = 455
    AND c.subject_id IN (
      SELECT
        subject_id
      FROM ICUStaysInfo
    )
    AND c.hadm_id IN (
      SELECT
        hadm_id
      FROM ICUStaysInfo
    )
    AND c.stay_id IN (
      SELECT
        stay_id
      FROM ICUStaysInfo
    )
    AND c.charttime BETWEEN (
      SELECT
        intime
      FROM ICUStaysInfo
      WHERE
        ICUStaysInfo.subject_id = c.subject_id AND ICUStaysInfo.hadm_id = c.hadm_id AND ICUStaysInfo.stay_id = c.stay_id
    ) AND (
      SELECT
        intime
      FROM ICUStaysInfo
      WHERE
        ICUStaysInfo.subject_id = c.subject_id AND ICUStaysInfo.hadm_id = c.hadm_id AND ICUStaysInfo.stay_id = c.stay_id
    ) + INTERVAL '24' HOUR
),
First24HoursSBP AS (
  SELECT
    sbp
  FROM SBPMeasurements
)
SELECT
  STDDEV(sbp)
FROM First24HoursSBP;