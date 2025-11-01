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
    a.insurance,
    d.long_title AS principal_diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.seq_num = 1
), FilteredAdmissions AS (
  SELECT
    ad.subject_id,
    ad.hadm_id
  FROM
    AdmissionDetails AS ad
  JOIN
    PatientDemographics AS pd
    ON ad.subject_id = pd.subject_id
  WHERE
    pd.gender = 'F'
    AND pd.insurance = 'Medicare'
    AND pd.anchor_age BETWEEN 65 AND 75
    AND ad.admission_type = 'TRANSFER'
    AND ad.admission_location = 'OTHER HOSPITAL'
    AND ad.principal_diagnosis LIKE '%heart failure%'
)
SELECT
  COUNT(hadm_id)
FROM
  FilteredAdmissions;