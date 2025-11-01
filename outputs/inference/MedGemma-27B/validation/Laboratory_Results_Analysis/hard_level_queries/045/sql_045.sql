WITH PatientAsthma AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 52 AND 62
    AND d.icd_code = 'J45.909' -- Asthma exacerbation, unspecified severity
), PatientAsthmaAdmission AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN PatientAsthma AS pa
    ON a.subject_id = pa.subject_id
), LabInstability AS (
  SELECT
    paa.subject_id,
    paa.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom,
    dli.label AS lab_name
  FROM PatientAsthmaAdmission AS paa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON paa.subject_id = le.subject_id AND paa.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    le.charttime BETWEEN paa.admittime AND TIMESTAMP_ADD(paa.admittime, INTERVAL 72 HOUR)
    AND dli.category = 'Laboratory'
), LabInstabilityScore AS (
  SELECT
    subject_id,
    hadm_id,
    AVG(valuenum) AS avg_lab_value
  FROM LabInstability
  GROUP BY
    subject_id,
    hadm_id
), LabInstabilityScorePercentile AS (
  SELECT
    subject_id,
    hadm_id,
    PERCENTILE_CONT(avg_lab_value, 0.90) AS p90_lab_instability_score
  FROM LabInstabilityScore
  GROUP BY
    subject_id,
    hadm_id
), TopDecile AS (
  SELECT
    subject_id,
    hadm_id
  FROM LabInstabilityScorePercentile
  WHERE
    avg_lab_value >= p90_lab_instability_score
), Mortality AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN TopDecile AS td
    ON a.subject_id = td.subject_id AND a.hadm_id = td.hadm_id
), LOS AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN TopDecile AS td
    ON a.subject_id = td.subject_id AND a.hadm_id = td.hadm_id
), CriticalLabEvents AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT le.itemid) AS critical_lab_events
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN TopDecile AS td
    ON a.subject_id = td.subject_id AND a.hadm_id = td.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON a.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
  WHERE
    le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a;