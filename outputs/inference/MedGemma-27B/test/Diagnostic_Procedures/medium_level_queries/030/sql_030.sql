WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 58
), AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age = 58
), DiagnosisInfo AS (
  SELECT
    a.hadm_id
  FROM
    AdmissionInfo AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'K92%' -- Upper GI bleeding ICD-10 codes
  GROUP BY
    a.hadm_id
), ProcedureInfo AS (
  SELECT
    a.hadm_id,
    p.icd_code
  FROM
    AdmissionInfo AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    ON a.hadm_id = p.hadm_id
), StayDuration AS (
  SELECT
    hadm_id,
    -- Calculate length of stay in days
    (
      CASE
        WHEN deathtime IS NOT NULL
        THEN TIMESTAMP_DIFF(deathtime, admittime, DAY)
        ELSE TIMESTAMP_DIFF(dischtime, admittime, DAY)
      END
    ) AS los_days
  FROM
    AdmissionInfo
), ProcedureCounts AS (
  SELECT
    s.hadm_id,
    s.los_days,
    COUNT(p.icd_code) AS procedure_count
  FROM
    StayDuration AS s
  JOIN
    ProcedureInfo AS p
    ON s.hadm_id = p.hadm_id
  WHERE
    s.los_days BETWEEN 1 AND 8
  GROUP BY
    s.hadm_id,
    s.los_days
), ProcedureCountsGrouped AS (
  SELECT
    los_days,
    procedure_count
  FROM
    ProcedureCounts
  WHERE
    los_days BETWEEN 1 AND 4
  UNION ALL
  SELECT
    los_days,
    procedure_count
  FROM
    ProcedureCounts
  WHERE
    los_days BETWEEN 5 AND 8
)
SELECT
  los_days,
  APPROX_QUANTILES(procedure_count, 3) AS p25,
  p50,
  p75
FROM
  ProcedureCountsGrouped
GROUP BY
  los_days
ORDER BY
  los_days;