WITH PatientInfo AS (
  -- Select subject_id, gender, and anchor_age for patients
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 40 AND 50
), AdmissionInfo AS (
  -- Select hadm_id and admission time for admissions
  SELECT
    hadm_id,
    admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
), DiagnosisInfo AS (
  -- Select hadm_id and icd_code for diagnoses
  SELECT
    hadm_id,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_version = 9 -- Assuming ICD-9 for stroke codes
), ICUStayInfo AS (
  -- Select stay_id, hadm_id, and intime for ICU stays
  SELECT
    stay_id,
    hadm_id,
    intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
), ProcedureInfo AS (
  -- Select hadm_id and chartdate for procedures
  SELECT
    hadm_id,
    chartdate
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE
    icd_version = 9 -- Assuming ICD-9 for procedure codes
), ProcedureCount AS (
  -- Count the number of procedures for each hadm_id within the first 72 hours
  SELECT
    p.hadm_id,
    COUNT(p.hadm_id) AS procedure_count
  FROM
    ProcedureInfo p
  WHERE
    p.chartdate BETWEEN (
      SELECT
        a.admittime
      FROM
        AdmissionInfo a
      WHERE
        a.hadm_id = p.hadm_id
    ) AND (
      SELECT
        a.admittime
      FROM
        AdmissionInfo a
      WHERE
        a.hadm_id = p.hadm_id
    ) + INTERVAL '72' HOUR
  GROUP BY
    p.hadm_id
), MortalityInfo AS (
  -- Select hadm_id and hospital_expire_flag for mortality information
  SELECT
    hadm_id,
    hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
), LOSInfo AS (
  -- Calculate the length of stay for each ICU stay
  SELECT
    i.hadm_id,
    i.los AS icu_los
  FROM
    ICUStayInfo i
)
SELECT
  CASE
    WHEN d.icd_code LIKE '430%' THEN 'Hemorrhagic Stroke'
    ELSE 'Other'
  END AS diagnosis_group,
  PERCENTILE_CONT(pc.procedure_count, 0.90) AS percentile_90_procedures,
  AVG(l.icu_los) AS avg_icu_los,
  AVG(m.hospital_expire_flag) AS avg_mortality
FROM
  PatientInfo pi
JOIN
  AdmissionInfo ai ON pi.subject_id = ai.subject_id
JOIN
  DiagnosisInfo d ON ai.hadm_id = d.hadm_id
JOIN
  ICUStayInfo i ON ai.hadm_id = i.hadm_id
JOIN
  ProcedureCount pc ON ai.hadm_id = pc.hadm_id
JOIN
  MortalityInfo m ON ai.hadm_id = m.hadm_id
JOIN
  LOSInfo l ON ai.hadm_id = l.hadm_id
WHERE
  d.icd_code LIKE '430%' -- Hemorrhagic stroke codes in ICD-9
GROUP BY
  diagnosis_group;