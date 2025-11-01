WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 72 AND 82
), AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admission_type,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientInfo AS pi
    ON a.subject_id = pi.subject_id
), ProcedureInfo AS (
  SELECT
    p.hadm_id,
    p.seq_num,
    p.icd_code,
    p.icd_version,
    d.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    d.long_title LIKE '%imaging%'
), ProcedureCounts AS (
  SELECT
    ai.hadm_id,
    COUNT(pi.seq_num) AS procedure_count
  FROM
    AdmissionInfo AS ai
  LEFT JOIN
    ProcedureInfo AS pi
    ON ai.hadm_id = pi.hadm_id
  GROUP BY
    ai.hadm_id
), ICUInfo AS (
  SELECT
    a.hadm_id,
    CASE
      WHEN a.los > 0 THEN 1
      ELSE 0
    END AS icu_use
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS a
  INNER JOIN
    AdmissionInfo AS ai
    ON a.hadm_id = ai.hadm_id
)
SELECT
  CASE
    WHEN ai.los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN ai.los BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Other'
  END AS los_group,
  icu.icu_use,
  COUNT(DISTINCT ai.hadm_id) AS admission_count,
  AVG(pc.procedure_count) AS mean_diagnostic_imaging_procedures
FROM
  AdmissionInfo AS ai
LEFT JOIN
  ProcedureCounts AS pc
  ON ai.hadm_id = pc.hadm_id
LEFT JOIN
  ICUInfo AS icu
  ON ai.hadm_id = icu.hadm_id
GROUP BY
  los_group,
  icu.icu_use
ORDER BY
  los_group,
  icu.icu_use;