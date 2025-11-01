WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 42 AND 52
), DiagnosisInfo AS (
  SELECT
    p.subject_id,
    d.icd_code
  FROM PatientInfo AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code = '410' -- AMI code
), ICUStayInfo AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM PatientInfo AS p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON p.subject_id = i.subject_id
), ProcedureInfo AS (
  SELECT
    i.subject_id,
    i.stay_id,
    p.itemid,
    p.charttime
  FROM ICUStayInfo AS i
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS p
    ON i.subject_id = p.subject_id AND i.stay_id = p.stay_id
  WHERE
    p.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
), ProcedureCount AS (
  SELECT
    subject_id,
    stay_id,
    COUNT(DISTINCT itemid) AS distinct_procedures
  FROM ProcedureInfo
  GROUP BY
    subject_id,
    stay_id
), DiagnosticIntensity AS (
  SELECT
    subject_id,
    APPROX_QUANTILES(distinct_procedures, 10)[OFFSET(8)] AS p90_diagnostic_intensity
  FROM ProcedureCount
  GROUP BY
    subject_id
), HospitalLOS AS (
  SELECT
    subject_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS hospital_los
  FROM PatientInfo AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
), Mortality AS (
  SELECT
    subject_id,
    a.hospital_expire_flag
  FROM PatientInfo AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
), AgeMatchedControl AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 42 AND 52
), AMI_Patients AS (
  SELECT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject;