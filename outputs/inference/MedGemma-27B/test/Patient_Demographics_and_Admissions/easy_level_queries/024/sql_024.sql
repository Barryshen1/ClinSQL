WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 35 AND 45
), AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
), ProcedureInfo AS (
  SELECT
    p.hadm_id,
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    d.long_title LIKE '%CORONARY ARTERY BYPASS GRAFT%'
)
SELECT
  COUNT(DISTINCT ai.hadm_id) AS total_admissions,
  SUM(ai.hospital_expire_flag) AS total_deaths,
  (SUM(ai.hospital_expire_flag) / COUNT(DISTINCT ai.hadm_id)) * 100 AS mortality_percentage
FROM
  AdmissionInfo AS ai
INNER JOIN
  ProcedureInfo AS pi
  ON ai.hadm_id = pi.hadm_id;