WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 76
), DiagnosisInfo AS (
  SELECT
    p.subject_id,
    d.icd_code,
    d.seq_num
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN
    PatientInfo AS p
    ON d.subject_id = p.subject_id
  WHERE
    d.icd_code LIKE 'K92%' -- Lower GI bleed ICD-10 code
), AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    d.icd_code AS primary_diagnosis,
    d.seq_num AS primary_diagnosis_seq
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    DiagnosisInfo AS d
    ON a.subject_id = d.subject_id
    AND d.seq_num = 1 -- Primary diagnosis
  WHERE
    a.admission_type = 'EMERGENCY' -- Assuming LGIB usually presents as emergency
), ProcedureInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.chartdate,
    p.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  INNER JOIN
    AdmissionInfo AS a
    ON p.subject_id = a.subject_id
    AND p.hadm_id = a.hadm_id
  WHERE
    p.icd_code LIKE '77%' -- Radiography/CT codes
), StayDuration AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS stay_duration
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    AdmissionInfo AS ai
    ON a.hadm_id = ai.hadm_id
), ProcedureCount AS (
  SELECT
    s.hadm_id,
    s.subject_id,
    s.stay_duration,
    COUNT(p.icd_code) AS procedure_count
  FROM
    StayDuration AS s
  LEFT JOIN
    ProcedureInfo AS p
    ON s.hadm_id = p.hadm_id
  GROUP BY
    s.hadm_id,
    s.subject_id,
    s.stay_duration
)
SELECT
  pc.stay_duration,
  AVG(pc.procedure_count) AS mean_radiography_cts
FROM
  ProcedureCount AS pc
WHERE
  pc.stay_duration BETWEEN 1 AND 3
  OR pc.stay_duration BETWEEN 4 AND 7
GROUP BY
  pc.stay_duration
ORDER BY
  pc.stay_duration;