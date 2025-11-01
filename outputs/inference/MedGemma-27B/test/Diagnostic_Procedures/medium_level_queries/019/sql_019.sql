WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 42 AND 52
), Diagnosis AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los, -- Added los from admissions table
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code = 'I10.1' -- Acute pancreatitis
    AND a.subject_id IN (SELECT subject_id FROM PatientInfo)
), ProcedureInfo AS (
  SELECT
    p.hadm_id,
    p.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  INNER JOIN
    Diagnosis AS d
    ON p.hadm_id = d.hadm_id
), ProcedureCount AS (
  SELECT
    hadm_id,
    COUNT(icd_code) AS procedure_count
  FROM
    ProcedureInfo
  GROUP BY
    hadm_id
), LOSGroup AS (
  SELECT
    hadm_id,
    CASE
      WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE 'Other'
    END AS los_group
  FROM
    Diagnosis -- Use Diagnosis CTE as it contains hadm_id and los
)
SELECT
  lg.los_group,
  COUNT(DISTINCT lg.hadm_id) AS patient_count,
  AVG(pc.procedure_count) AS mean_procedures,
  MIN(pc.procedure_count) AS min_procedures,
  MAX(pc.procedure_count) AS max_procedures
FROM
  LOSGroup AS lg
INNER JOIN
  ProcedureCount AS pc
  ON lg.hadm_id = pc.hadm_id
WHERE
  lg.los_group IN ('1-4 days', '5-7 days')
GROUP BY
  lg.los_group
ORDER BY
  lg.los_group;