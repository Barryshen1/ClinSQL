WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hadm_id,
    a.hospital_expire_flag,
    d.long_title AS diagnosis_title
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND d.icd_code = 'J45.909' -- Asthma exacerbation, unspecified severity
), ICUStays AS (
  SELECT
    ps.subject_id,
    ps.hadm_id,
    ps.anchor_age,
    ps.gender,
    ps.diagnosis_title,
    ps.admittime,
    ps.dischtime,
    ps.hospital_expire_flag,
    is_icu.stay_id,
    is_icu.intime,
    is_icu.outtime,
    is_icu.los
  FROM PatientCohort AS ps
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS is_icu
    ON ps.subject_id = is_icu.subject_id
    AND ps.hadm_id = is_icu.hadm_id
), ProcedureCounts AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    COUNT(pe.itemid) AS procedure_count
  FROM ICUStays AS icu
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON icu.subject_id = pe.subject_id
    AND icu.hadm_id = pe.hadm_id
    AND icu.stay_id = pe.stay_id
    AND pe.starttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)
  GROUP BY
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
), QuartileAnalysis AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.stay_id,
    pc.procedure_count,
    pc.intime,
    pc.outtime,
    icu.los,
    icu.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY pc.procedure_count) AS procedure_quartile
  FROM ProcedureCounts AS pc
  JOIN ICUStays AS icu
    ON pc.subject_id = icu.subject_id
    AND pc.hadm_id = icu.hadm_id
    AND pc.stay_id = icu.stay_id
)
SELECT
  procedure_quartile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los) AS mean_hospital_los_days,
  AVG(hospital_expire_flag) AS hospital_mortality
FROM QuartileAnalysis
GROUP BY
  procedure_quartile
ORDER BY
  procedure_quartile;