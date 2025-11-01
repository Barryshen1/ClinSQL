WITH PatientCohort AS (
  -- Identify the target patient's subject_id
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age = 47
),
ValveProcedures AS (
  -- Identify all valve repair/replacement procedures using ICD codes
  SELECT
    p.subject_id,
    p.hadm_id,
    p.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
  ON
    p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    d.long_title LIKE '%valve%' AND (d.long_title LIKE '%repair%' OR d.long_title LIKE '%replacement%')
),
PatientProcedures AS (
  -- Link the target patient to their valve procedures
  SELECT
    vp.subject_id,
    vp.hadm_id
  FROM
    PatientCohort AS pc
  INNER JOIN
    ValveProcedures AS vp
  ON
    pc.subject_id = vp.subject_id
),
ProcedureCounts AS (
  -- Count the distinct number of valve procedures (admissions) for the target patient
  SELECT
    subject_id,
    COUNT(DISTINCT hadm_id) AS distinct_procedures
  FROM
    PatientProcedures
  GROUP BY
    subject_id
)
-- Calculate the average distinct valve procedures for the target patient's cohort
SELECT
  AVG(distinct_procedures) AS average_distinct_valve_procedures
FROM
  ProcedureCounts
WHERE
  subject_id IN (
    SELECT
      subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'M' AND anchor_age BETWEEN 42 AND 52
  );