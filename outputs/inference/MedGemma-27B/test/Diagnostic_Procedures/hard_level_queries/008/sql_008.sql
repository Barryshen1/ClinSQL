WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
),
UGIBDiagnosis AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.icd_code LIKE '53%' -- ICD-9 codes for upper GI bleeding start with 53
    AND d.icd_version = 9
),
ICUStays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  WHERE
    s.stay_id IS NOT NULL
),
Procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    p.charttime,
    p.itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS p
),
ProcedureCounts AS (
  SELECT
    ugib.subject_id,
    ugib.hadm_id,
    icu.stay_id,
    COUNT(proc.itemid) AS procedure_count
  FROM
    UGIBDiagnosis AS ugib
  INNER JOIN
    ICUStays AS icu ON ugib.subject_id = icu.subject_id AND ugib.hadm_id = icu.hadm_id
  INNER JOIN
    Procedures AS proc ON icu.subject_id = proc.subject_id AND icu.hadm_id = proc.hadm_id AND icu.stay_id = proc.stay_id
  WHERE
    proc.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY
    ugib.subject_id,
    ugib.hadm_id,
    icu.stay_id
),
PatientCohort AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    icu.stay_id,
    pi.age,
    pi.gender,
    icu.intime,
    icu.outtime,
    pc.procedure_count
  FROM
    PatientInfo AS pi
  INNER JOIN
    UGIBDiagnosis AS ugib ON pi.subject_id = ugib.subject_id
  INNER JOIN
    ICUStays AS icu ON ugib.subject_id = icu.subject_id AND ugib.hadm_id = icu.hadm_id
  INNER JOIN
    ProcedureCounts AS pc ON ugib.subject_id = pc.subject_id AND ugib.hadm_id = pc.hadm_id AND icu.stay_id = pc.stay_id
  WHERE
    pi.gender = 'M'
    AND pi.age BETWEEN 48 AND 58
)
SELECT
  NTILE(5) OVER (ORDER BY procedure_count) AS procedure_quintile,
  AVG(procedure_count) AS avg_procedures,
  AVG(TIMESTAMP_DIFF(icu.outtime, icu.intime, DAY)) AS avg_los_days,
  AVG(CASE WHEN icu.outtime IS NULL THEN 0 ELSE 1 END) AS mortality_percentage
FROM
  PatientCohort
GROUP BY
  procedure_quintile
ORDER BY
  procedure_quintile;