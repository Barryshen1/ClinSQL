WITH PatientCohort AS (
  -- Select patients matching the criteria: male, age 82-92, cardiogenic shock diagnosis
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    di.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON p.subject_id = di.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON p.subject_id = ic.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND di.icd_code = 'R57.0' -- Cardiogenic shock ICD-10 code
),
ProcedureCounts AS (
  -- Count procedures within the first 24 hours of ICU stay for each patient
  SELECT
    pc.subject_id,
    pc.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM
    PatientCohort AS pc
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON pc.subject_id = pe.subject_id
    AND pc.stay_id = pe.stay_id
    AND pe.starttime BETWEEN pc.intime AND TIMESTAMP_ADD(pc.intime, INTERVAL 24 HOUR)
  GROUP BY
    pc.subject_id,
    pc.stay_id
),
HospitalLOS AS (
  -- Calculate hospital length of stay for each patient
  SELECT
    h.subject_id,
    h.hadm_id,
    TIMESTAMP_DIFF(h.dischtime, h.admittime, DAY) AS hospital_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS h
  WHERE
    h.subject_id IN (SELECT subject_id FROM PatientCohort)
),
Mortality AS (
  -- Determine in-hospital mortality for each patient
  SELECT
    h.subject_id,
    h.hadm_id,
    CASE WHEN h.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS h
  WHERE
    h.subject_id IN (SELECT subject_id FROM PatientCohort)
)
SELECT
  -- Calculate quintiles based on procedure count
  NTILE(5) OVER (ORDER BY pc.procedure_count) AS procedure_quintile,
  AVG(pc.procedure_count) AS mean_procedure_count,
  AVG(hlos.hospital_los) AS mean_hospital_los,
  AVG(m.mortality) * 100 AS in_hospital_mortality_percentage
FROM
  ProcedureCounts AS pc
INNER JOIN
  HospitalLOS AS hlos
  ON pc.subject_id = hlos.subject_id
INNER JOIN
  Mortality AS m
  ON pc.subject_id = m.subject_id
GROUP BY
  procedure_quintile
ORDER BY
  procedure_quintile;