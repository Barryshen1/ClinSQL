WITH PatientCohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND d.icd_code IN ('J12.9', 'J13', 'J15.1', 'J15.2', 'J15.3', 'J15.4', 'J15.5', 'J15.6', 'J15.7', 'J15.8', 'J15.9', 'J18.1', 'J18.2', 'J18.9') -- Pneumonia ICD-10 codes
    AND d.icd_code IN ('J44.1', 'J44.9') -- COPD ICD-10 codes
    AND a.admission_type = 'EMERGENCY'
    AND a.hospital_expire_flag = 0
    AND a.dischtime IS NOT NULL -- Ensure the patient was discharged to calculate LOS
)
SELECT
  PERCENTILE_CONT(0.75, a.los) AS percentile_75_los
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN PatientCohort AS pc
  ON a.subject_id = pc.subject_id;