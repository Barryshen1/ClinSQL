WITH MedicationComplexity AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug,
    p.route,
    CASE
      WHEN p.drug IN ('Warfarin', 'Insulin', 'Heparin', 'Morphine', 'Furosemide', 'Digoxin', 'Amiodarone', 'Lisinopril', 'Metformin', 'Atorvastatin') THEN 2
      ELSE 1
    END AS drug_weight
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.drug IS NOT NULL
    AND p.route IS NOT NULL
  UNION ALL
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.medication,
    p.route,
    CASE
      WHEN p.medication IN ('Warfarin', 'Insulin', 'Heparin', 'Morphine', 'Furosemide', 'Digoxin', 'Amiodarone', 'Lisinopril', 'Metformin', 'Atorvastatin') THEN 2
      ELSE 1
    END AS drug_weight
  FROM
    `physionet-data.mimiciv_3_1_hosp.pharmacy` AS p
  WHERE
    p.medication IS NOT NULL
    AND p.route IS NOT NULL
),
MedicationComplexityScore AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT drug) AS unique_drugs,
    SUM(drug_weight) AS high_risk_drugs,
    COUNT(DISTINCT route) AS unique_routes,
    (COUNT(DISTINCT drug) + 2 * SUM(drug_weight) + COUNT(DISTINCT route)) AS complexity_score
  FROM
    MedicationComplexity
  WHERE
    starttime BETWEEN TIMESTAMP_SUB(admit_time, INTERVAL 7 DAY) AND admit_time
    AND stoptime >= admit_time
    AND (stoptime IS NULL OR stoptime > admit_time)
  GROUP BY
    subject_id,
    hadm_id
),
PatientData AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.gender,
    p.anchor_age,
    p.dod,
    CASE
      WHEN a.hospital_expire_flag = TRUE THEN 1
      ELSE 0
    END AS in_hospital_mortality
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.admission_type = 'EMERGENCY'
    AND a.hospital_expire_flag = FALSE
),
ReadmissionData AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime AS readmission_admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (SELECT subject_id FROM PatientData)
    AND a.admittime > (SELECT MAX(dischtime) FROM PatientData WHERE PatientData.subject_id = a.subject_id)
    AND a.admission_type = 'EMERGENCY'
),
FinalData AS (
  SELECT
    pd.subject_id,
    pd.hadm_id,
    pd.admittime,
    pd.dischtime,
    pd.deathtime,
    pd.in_hospital_mortality,
    mcs.complexity_score,
    rd.readmission_admittime
  FROM
    PatientData AS pd
  JOIN
    MedicationComplexityScore AS mcs
    ON pd.subject_id = mcs.subject_id AND pd.hadm_id = mcs.hadm_id
  LEFT JOIN
    ReadmissionData AS;