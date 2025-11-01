WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND i.stay_id = (
      SELECT
        MIN(stay_id)
      FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS i2
      WHERE
        i2.subject_id = i.subject_id
        AND i2.hadm_id = i.hadm_id
    )
), Diagnosis AS (
  SELECT
    subject_id,
    hadm_id,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code = 'J80'
), ProcedureEvents AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE
    charttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 72 HOUR)
), ProcedureCount AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.stay_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedures
  FROM
    PatientCohort AS pc
  INNER JOIN
    ProcedureEvents AS pe
    ON pc.subject_id = pe.subject_id
    AND pc.hadm_id = pe.hadm_id
    AND pc.stay_id = pe.stay_id
  GROUP BY
    pc.subject_id,
    pc.hadm_id,
    pc.stay_id
), AllICUPatients AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    los,
    hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
)
SELECT
  'ARDS Cohort' AS cohort,
  AVG(pc.distinct_procedures) AS mean_procedures,
  PERCENTILE_CONT(pc.distinct_procedures, 0.75) AS p75_procedures,
  PERCENTILE_CONT(pc.distinct_procedures, 0.90) AS p90_procedures,
  AVG(a.los) AS mean_los,
  AVG(CAST(a.hospital_expire_flag AS INT64)) AS mean_mortality
FROM
  ProcedureCount AS pc
INNER JOIN
  PatientCohort AS a
  ON pc.subject_id = a.subject_id
  AND pc.hadm_id = a.hadm_id
  AND pc.stay_id = a.stay_id
UNION ALL
SELECT
  'All ICU Patients' AS cohort,
  AVG(a.distinct_procedures) AS mean_procedures,
  PERCENTILE_CONT(a.distinct_procedures, 0.75) AS p75_procedures,
  PERCENTILE_CONT(a.distinct_procedures, 0.90) AS p90_procedures,
  AVG(a.los) AS mean_los,
  AVG(CAST(a.hospital_expire_flag AS INT64)) AS mean_mortality
FROM
  AllICUPatients AS a
INNER JOIN
  ProcedureCount AS pc
  ON a.subject_id = pc;