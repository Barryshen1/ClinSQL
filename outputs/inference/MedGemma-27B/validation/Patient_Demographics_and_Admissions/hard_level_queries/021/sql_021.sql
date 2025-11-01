WITH PatientCohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.insurance = 'Medicare'
    AND p.anchor_age BETWEEN 82 AND 92
    AND a.admission_location = 'EMERGENCY'
    AND d.seq_num = 1 -- Principal diagnosis
    AND (
      (
        d.icd_version = 9 AND d.icd_code = '577.0'
      ) OR (
        d.icd_version = 10 AND d.icd_code LIKE 'K85%'
      )
    )
    AND a.dischtime IS NOT NULL -- Recorded discharge
)
SELECT
  COUNT(hadm_id)
FROM PatientCohort;