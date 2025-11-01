WITH PatientCohort AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
), DiagnosisCohort AS (
  SELECT DISTINCT
    d.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  INNER JOIN
    PatientCohort AS p
    ON d.subject_id = p.subject_id
  WHERE
    di.long_title LIKE '%Upper Gastrointestinal Bleeding%'
    OR di.long_title LIKE '%COPD Exacerbation%'
), AdmissionCohort AS (
  SELECT DISTINCT
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    DiagnosisCohort AS dc
    ON a.subject_id = dc.subject_id
)
SELECT
  PERCENTILE_CONT(0.5, TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS median_los
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
INNER JOIN
  AdmissionCohort AS ac
  ON a.hadm_id = ac.hadm_id;