WITH PatientDemographics AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    insurance
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionDetails AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.admission_type,
    a.admission_location,
    d.long_title AS diagnosis_description
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag ON a.hadm_id = diag.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    diag.seq_num = 1
), FilteredAdmissions AS (
  SELECT
    ad.subject_id,
    ad.hadm_id
  FROM
    AdmissionDetails AS ad
  INNER JOIN
    PatientDemographics AS pd ON ad.subject_id = pd.subject_id
  WHERE
    pd.gender = 'M'
    AND pd.insurance = 'Medicare'
    AND pd.anchor_age BETWEEN 77 AND 87
    AND ad.admission_location = 'EMERGENCY'
    AND ad.diagnosis_description LIKE '%Pneumonia%'
)
SELECT
  COUNT(hadm_id) AS total_index_admissions
FROM
  FilteredAdmissions;