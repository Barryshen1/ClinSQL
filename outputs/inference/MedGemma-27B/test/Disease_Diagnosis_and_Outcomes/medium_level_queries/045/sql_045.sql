WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.hospital_expire_flag,
    a.hadm_id,
    a.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.admission_type = 'EMERGENCY'
), Diagnosis AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.stay_id,
    pc.admittime,
    pc.dischtime,
    pc.deathtime,
    pc.hospital_expire_flag,
    d.icd_code
  FROM PatientCohort AS pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON pc.subject_id = d.subject_id AND pc.hadm_id = d.hadm_id
  WHERE
    d.icd_code IN ('J12.9', 'J13', 'J15.9', 'J18.9', 'P32.0', 'P32.1', 'P32.8', 'P32.9')
), ICUStay AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.stay_id,
    d.admittime,
    d.dischtime,
    d.deathtime,
    d.hospital_expire_flag,
    i.intime,
    i.outtime,
    i.los
  FROM Diagnosis AS d
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON d.subject_id = i.subject_id AND d.hadm_id = i.hadm_id
), Mortality AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.admittime,
    icu.dischtime,
    icu.deathtime,
    icu.hospital_expire_flag,
    icu.intime,
    icu.outtime,
    icu.los,
    CASE
      WHEN icu.deathtime IS NOT NULL
      THEN 1
      ELSE 0
    END AS mortality
  FROM ICUStay AS icu
), LOSGroup AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.stay_id,
    m.admittime,
    m.dischtime,
    m.deathtime,
    m.hospital_expire_flag,
    m.intime,
    m.outtime,
    m.los,
    m.mortality,
    CASE
      WHEN m.los <= 7 THEN '<=7'
      ELSE '>7'
    END AS los_group
  FROM Mortality AS m
), Day1ICU AS (
  SELECT
    lg.subject_id,
    lg.hadm_id,
    lg.stay_id,
    lg.los_group,
    lg.mortality,
    CASE
      WHEN lg.intime < TIMESTAMP_ADD(lg.admittime, INTERVAL 1 DAY) THEN 1
      ELSE 0
    END AS day1_icu
  FROM LOSGroup AS lg
), MechVent AS (
  SELECT
    lg.subject_id,
    lg.hadm_id,
    lg.stay_id,
    lg.los_group,
    lg.mortality,
    lg.day1_icu,
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        WHERE
          ce.subject_;