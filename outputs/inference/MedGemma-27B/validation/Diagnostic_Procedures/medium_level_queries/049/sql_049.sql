WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    AND a.hospital_expire_flag = 0 -- Exclude patients who died in hospital
),
SepsisCohort AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.admittime,
    pc.dischtime,
    pc.anchor_age,
    pc.gender
  FROM PatientCohort AS pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON pc.subject_id = dx.subject_id AND pc.hadm_id = dx.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
    ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
  WHERE
    ddx.long_title LIKE '%sepsis%'
    AND dx.icd_code NOT LIKE 'R65.2%' -- Exclude septic shock
),
AdmissionLength AS (
  SELECT
    sc.hadm_id,
    sc.subject_id,
    sc.admittime,
    sc.dischtime,
    -- Calculate admission length in days
    CAST(TIMESTAMP_DIFF(sc.dischtime, sc.admittime, DAY) AS INT64) AS admission_length
  FROM SepsisCohort AS sc
),
ProcedureCount AS (
  SELECT
    al.hadm_id,
    al.subject_id,
    al.admission_length,
    COUNT(DISTINCT pr.icd_code) AS procedure_count
  FROM AdmissionLength AS al
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
    ON al.hadm_id = pr.hadm_id
  GROUP BY
    al.hadm_id,
    al.subject_id,
    al.admission_length
)
SELECT
  admission_length,
  AVG(procedure_count) AS mean_procedure_count
FROM ProcedureCount
WHERE
  admission_length BETWEEN 1 AND 3
  OR admission_length BETWEEN 4 AND 7
GROUP BY
  admission_length
ORDER BY
  admission_length;