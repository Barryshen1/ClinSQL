WITH PatientInfo AS (
  -- Select subject_id and gender for patients matching the age criteria
  SELECT
    subject_id,
    gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age BETWEEN 49 AND 59
), PatientDiagnosis AS (
  -- Select subject_id and hadm_id for patients diagnosed with sepsis (no septic shock)
  SELECT
    p.subject_id,
    p.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    d.long_title LIKE '%sepsis%'
    AND p.seq_num = 1 -- Assuming the first diagnosis is the primary one
    AND p.hadm_id NOT IN (
      -- Exclude patients with septic shock diagnosis
      SELECT
        hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        icd_code = 'R6521' -- ICD-10 code for septic shock
    )
), AdmissionInfo AS (
  -- Select admission details including ICU stay information
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
), PatientComorbidities AS (
  -- Select comorbidities (CKD and diabetes) for each patient
  SELECT
    p.subject_id,
    p.hadm_id,
    MAX(CASE WHEN d.long_title LIKE '%chronic kidney disease%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN d.long_title LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    p.seq_num > 1 -- Exclude primary diagnosis
  GROUP BY
    p.subject_id,
    p.hadm_id
), CombinedData AS (
  -- Combine all the information
  SELECT
    pi.subject_id,
    pi.gender,;