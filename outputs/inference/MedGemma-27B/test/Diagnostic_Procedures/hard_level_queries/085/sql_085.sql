WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 92
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.insurance,
    a.language,
    a.marital_status,
    a.race,
    a.edregtime,
    a.edouttime,
    a.transfertime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
), DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
    AND d.seq_num = 1
    AND d.icd_code LIKE '571%'
), ICUStayInfo AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  WHERE
    i.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
    AND i.stay_id = 1
), ProcedureInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    p.charttime,
    p.itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS p
  WHERE
    p.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
), ProcedureCount AS (
  SELECT
    ps.subject_id,
    ps.hadm_id,
    ps.stay_id,
    COUNT(DISTINCT ps.itemid) AS distinct_procedures
  FROM
    ProcedureInfo AS ps
  WHERE
    ps.charttime BETWEEN (
      SELECT
        i.intime
      FROM
        ICUStayInfo AS i
      WHERE
        i.subject_id = ps.subject_id
        AND i.hadm_id = ps.hadm_id
        AND i.stay_id = ps.stay_id
    ) AND (
      SELECT
        DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
      FROM
        ICUStayInfo AS i
      WHERE
        i.subject_id = ps.subject_id
        AND i.hadm_id = ps.hadm_id
        AND i.stay_id = ps.stay_id
    )
), PatientICUStay AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag,
    pc.distinct_procedures
  FROM
    AdmissionInfo AS a
  JOIN
    ICUStayInfo AS i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN
    ProcedureCount AS pc ON a.subject_id = pc.subject_id AND a.hadm_id = pc.hadm_id AND i.stay_id = pc.stay_id
  WHERE
    a.hospital_expire_flag = 1
), PatientQuintiles AS (
  SELECT;