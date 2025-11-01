WITH PatientHF AS (
  -- Identify patients with heart failure (HF) diagnosis
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 72 AND 82
    AND d.icd_code LIKE 'I50%' -- ICD-10 codes for heart failure
    AND d.icd_version = 10
),
AdmissionsHF AS (
  -- Filter admissions for patients identified with HF
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    a.admission_location,
    a.discharge_location
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN PatientHF AS phf
    ON a.subject_id = phf.subject_id
),
ICUStays AS (
  -- Identify ICU stays for the selected admissions
  SELECT
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM AdmissionsHF AS a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON a.hadm_id = i.hadm_id
),
ComorbidityCount AS (
  -- Calculate comorbidity count for each patient
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM AdmissionsHF AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.seq_num = 1 -- Consider only primary diagnoses for comorbidity count
  GROUP BY
    a.subject_id,
    a.hadm_id
),
CombinedData AS (
  -- Combine admission data, ICU stay data, and comorbidity count
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    CASE
      WHEN i.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_status,
    i.los AS icu_los,
    c.comorbidity_count
  FROM AdmissionsHF AS a
  LEFT JOIN ICUStays AS i
    ON a.hadm_id = i.hadm_id
  LEFT JOIN ComorbidityCount AS c
    ON a.hadm_id = c.hadm_id
)
SELECT
  icu_status,
  CASE
    WHEN icu_los <= 3 THEN '≤3 days'
    WHEN icu_los BETWEEN 4 AND 6 THEN '4–6 days'
    WHEN icu_los BETWEEN 7 AND 10 THEN '7–10 days'
    ELSE '>10 days'
  END AS los_category,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality,
  AVG(DATE_DIFF(dischtime, admittime, DAY)) AS median_los,
  AVG(comorbidity_count) AS average_comorbidity_count
FROM CombinedData
GROUP BY
  icu_status,
  los_category
ORDER BY
  icu_status,
  los_category;