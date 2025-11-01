WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    subject_id = 57 -- Specific patient ID
),
Admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    d.long_title AS admission_diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag ON a.hadm_id = diag.hadm_id AND diag.seq_num = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM PatientInfo)
    AND d.long_title LIKE '%AMI%' -- Filter for Acute Myocardial Infarction
),
ICUStays AS (
  SELECT
    s.stay_id,
    s.hadm_id,
    s.subject_id,
    s.intime,
    s.outtime,
    s.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN
    Admissions AS a ON s.hadm_id = a.hadm_id
),
TroponinEvents AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS troponin_value,
    c.valueuom AS troponin_uom
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS d ON c.itemid = d.itemid
  WHERE
    c.subject_id IN (SELECT subject_id FROM PatientInfo)
    AND d.label LIKE '%Troponin T%'
    AND c.valuenum > 0.01
),
FirstTroponin AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(charttime) AS first_troponin_time,
    MIN(valuenum) AS first_troponin_value,
    MIN(valueuom) AS first_troponin_uom
  FROM
    TroponinEvents
  GROUP BY
    subject_id,
    hadm_id
),
FilteredAdmissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_diagnosis,
    ft.first_troponin_time,
    ft.first_troponin_value,
    ft.first_troponin_uom
  FROM
    Admissions AS a
  JOIN
    FirstTroponin AS ft ON a.hadm_id = ft.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM PatientInfo)
    AND a.gender = 'F'
    AND a.anchor_age BETWEEN 52 AND 62
)
SELECT
  COUNT(hadm_id) AS patient_admission_count,
  AVG(anchor_age) AS mean_age,
  AVG(los) AS mean_los,
  AVG(first_troponin_value) AS mean_first_troponin_value,
  AVG(first_troponin_uom) AS mean_first_troponin_uom,
  SUM(hospital_expire_flag) AS in_hospital_mortality_count
FROM
  FilteredAdmissions;