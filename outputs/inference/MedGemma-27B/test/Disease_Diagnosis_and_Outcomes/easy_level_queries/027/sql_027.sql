WITH PatientDiagnosis AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 54
    AND d.icd_code = '530.0' -- ICD-9 code for upper GI bleed
    AND d.seq_num = 1 -- Primary diagnosis
    AND p.anchor_age BETWEEN 49 AND 59 -- Age group check
)
SELECT
  MAX(los) AS max_length_of_stay_days
FROM PatientDiagnosis;