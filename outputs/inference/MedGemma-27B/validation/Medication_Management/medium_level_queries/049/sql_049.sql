WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    subject_id = 71 -- Specific patient ID
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    PatientInfo AS p ON a.subject_id = p.subject_id
  WHERE
    a.subject_id = 71 -- Specific patient ID
), DiagnosisInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON a.hadm_id = d.hadm_id
  WHERE
    a.subject_id = 71 -- Specific patient ID
), MedicationInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug,
    p.drug_type,
    p.route
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.subject_id = 71 -- Specific patient ID
), ICUStayInfo AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.icustays` AS s
  WHERE
    s.subject_id = 71 -- Specific patient ID
), AntidiabeticClasses AS (
  SELECT DISTINCT
    drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    drug LIKE '%insulin%' OR drug LIKE '%metformin%' OR drug LIKE '%sulfonylurea%' OR drug LIKE '%glitazone%' OR drug LIKE '%glp-1%' OR drug LIKE '%sglt2%' OR drug LIKE '%dpp-4%'
), TimePeriods AS (
  SELECT
    m.hadm_id,
    m.starttime,
    m.stoptime,
    a.admittime,
    a.dischtime,
    CASE
      WHEN m.starttime < TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR) THEN 'First 72h'
      WHEN m.starttime >= TIMESTAMP_ADD(a.dischtime, INTERVAL -24 HOUR) THEN 'Final 24h'
      ELSE 'Other' -- Added ELSE clause
    END AS time_period
  FROM
    MedicationInfo AS m
  JOIN
    AdmissionInfo AS a ON m.hadm_id = a.hadm_id
), AntidiabeticUsage AS (
  SELECT
    tp.hadm_id,
    tp.time_period,
    m.drug,
    ac.drug AS antidiabetic_class
  FROM
    TimePeriods AS tp
  JOIN
    MedicationInfo AS m ON tp.hadm_id = m.hadm_id
  JOIN
    AntidiabeticClasses AS ac ON m.drug = ac.drug
  WHERE
    tp.time_period IN ('First 72h', 'Final 24h')
), UsageCounts AS (
  SELECT
    hadm_id,
    time_period,
    antidiabetic_class,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM
    AntidiabeticUsage;