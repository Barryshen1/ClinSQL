WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 58 AND 68
),
ProcedureCounts AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los,
    COUNT(p.seq_num) AS procedure_count
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    ON a.subject_id = p.subject_id AND a.hadm_id = p.hadm_id
  WHERE
    a.los BETWEEN 1 AND 7
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.los
)
SELECT
  COUNT(DISTINCT pc.subject_id) AS patient_count,
  COUNT(DISTINCT pc.hadm_id) AS admission_count,
  AVG(pc.procedure_count) AS mean_procedure_count,
  pc.los
FROM
  ProcedureCounts AS pc
JOIN
  PatientAge AS pa
  ON pc.subject_id = pa.subject_id
WHERE
  pc.los BETWEEN 1 AND 4
GROUP BY
  pc.los
UNION ALL
SELECT
  COUNT(DISTINCT pc.subject_id) AS patient_count,
  COUNT(DISTINCT pc.hadm_id) AS admission_count,
  AVG(pc.procedure_count) AS mean_procedure_count,
  pc.los
FROM
  ProcedureCounts AS pc
JOIN
  PatientAge AS pa
  ON pc.subject_id = pa.subject_id
WHERE
  pc.los BETWEEN 5 AND 7
GROUP BY
  pc.los;