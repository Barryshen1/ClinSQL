WITH PatientCohort AS (
  SELECT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age >= 75
    AND p.anchor_age <= 85
), DiagnosisCohort AS (
  SELECT DISTINCT
    pc.subject_id
  FROM PatientCohort AS pc
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON pc.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dc ON d.icd_code = dc.icd_code AND d.icd_version = dc.icd_version
  WHERE
    dc.long_title LIKE '%ischemic heart disease%'
    OR dc.long_title LIKE '%acute coronary syndrome%'
    OR dc.long_title LIKE '%COPD%'
), FinalCohort AS (
  SELECT DISTINCT
    dc.subject_id
  FROM DiagnosisCohort AS dc
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON dc.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dc2 ON d.icd_code = dc2.icd_code AND d.icd_version = dc2.icd_version
  WHERE
    dc2.long_title LIKE '%ischemic heart disease%'
    OR dc2.long_title LIKE '%acute coronary syndrome%'
    OR dc2.long_title LIKE '%COPD%'
)
SELECT
  PERCENTILE_CONT(0.75, a.los) AS percentile_75_los
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN FinalCohort AS fc ON a.subject_id = fc.subject_id;