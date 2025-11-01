WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age = 53
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    )
    AND a.admittime = (
      SELECT
        MIN(admittime)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions`
      WHERE
        subject_id = a.subject_id
    )
), ProcedureInfo AS (
  SELECT
    pi.subject_id,
    pi.hadm_id
  FROM AdmissionInfo AS pi
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON pi.subject_id = proc.subject_id AND pi.hadm_id = proc.hadm_id
  WHERE
    proc.icd_code = '33510'
), AgeGroupInfo AS (
  SELECT
    subject_id,
    hadm_id
  FROM AdmissionInfo
  WHERE
    anchor_age BETWEEN 48 AND 58
)
SELECT
  PERCENTILE_CONT(0.25, ai.hospital_expire_flag)
FROM AdmissionInfo AS ai
JOIN AgeGroupInfo AS agi
  ON ai.subject_id = agi.subject_id AND ai.hadm_id = agi.hadm_id
JOIN ProcedureInfo AS pi
  ON ai.subject_id = pi.subject_id AND ai.hadm_id = pi.hadm_id;