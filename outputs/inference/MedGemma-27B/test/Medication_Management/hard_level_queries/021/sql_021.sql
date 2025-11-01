WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
), NeutropeniaFever AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    MIN(le.charttime) AS first_neutropenia_time,
    MIN(le.charttime) AS first_fever_time
  FROM PatientCohort AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON p.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Neutrophil count'
    AND le.valuenum < 1500
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY
    p.subject_id,
    p.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime
  HAVING
    MIN(le.charttime) IS NOT NULL
), Fever AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    MIN(le.charttime) AS first_fever_time
  FROM PatientCohort AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON p.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Temperature'
    AND le.valuenum > 38
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY
    p.subject_id,
    p.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime
  HAVING
    MIN(le.charttime) IS NOT NULL
), CombinedCohort AS (
  SELECT
    nf.subject_id,
    nf.hadm_id,
    nf.admittime,
    nf.dischtime,
    nf.deathtime,
    nf.first_neutropenia_time,
    f.first_fever_time
  FROM NeutropeniaFever AS nf
  INNER JOIN Fever AS f
    ON nf.subject_id = f.subject_id AND nf.hadm_id = f.hadm_id
), MedicationCount AS (
  SELECT
    cc.subject_id,
    cc.hadm_id,
    COUNT(DISTINCT e.drug) AS unique_meds
  FROM CombinedCohort AS cc
  INNER JOIN `physionet-data.mimiciv;