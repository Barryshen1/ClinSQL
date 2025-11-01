WITH PatientDiagnosis AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code = 'I50.9' -- Acute decompensated heart failure
), PatientComorbidities AS (
  SELECT
    subject_id,
    COUNT(CASE WHEN icd_code = 'I50.9' THEN 1 ELSE NULL END) AS has_adhf,
    COUNT(CASE WHEN icd_code = 'N18.9' THEN 1 ELSE NULL END) AS has_ckd,
    COUNT(CASE WHEN icd_code = 'E11.9' THEN 1 ELSE NULL END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code IN ('I50.9', 'N18.9', 'E11.9')
  GROUP BY
    subject_id
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.los AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
), ICUStayInfo AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los
  FROM `physionet-data.mimiciv_3_1_hosp.icustays` AS i
)
SELECT
  CASE
    WHEN icu_los <= 7
    THEN '≤7 days'
    ELSE '>7 days'
  END AS los_group,
  CASE
    WHEN icu_intime IS NOT NULL
    THEN 'ICU admission'
    ELSE 'Non-ICU admission'
  END AS day_1_icu_status,
  COUNT(DISTINCT subject_id) AS total_patients,
  COUNT(DISTINCT CASE WHEN hospital_expire_flag = 1 THEN subject_id ELSE NULL END) AS mortality_count,
  COUNT(DISTINCT CASE WHEN has_ckd = 1 THEN subject_id ELSE NULL END) AS ckd_count,
  COUNT(DISTINCT CASE WHEN has_diabetes = 1 THEN subject_id ELSE NULL END) AS diabetes_count
FROM AdmissionInfo AS a
JOIN ICUStayInfo AS i
  ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
JOIN PatientComorbidities AS pc
  ON a.subject_id = pc.subject_id
JOIN PatientDiagnosis AS pd
  ON a.subject_id = pd.subject_id
WHERE
  a.subject_id IN (
    SELECT
      subject_id
    FROM PatientDiagnosis
  )
  AND a.gender = 'M'
  AND a.anchor_age BETWEEN 67 AND 77
GROUP BY
  1,
  2
ORDER BY
  1,
  2;