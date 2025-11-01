WITH PatientCohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND di.long_title LIKE '%COPD exacerbation%'
    AND d.seq_num = 1 -- Assuming the primary diagnosis is the first one
), ICUStays AS (
  SELECT
    ps.subject_id,
    ps.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    ic.hospital_expire_flag
  FROM PatientCohort AS ps
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON ps.subject_id = ic.subject_id AND ps.hadm_id = ic.hadm_id
), ProceduresInFirst72Hours AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedures
  FROM ICUStays AS icu
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON icu.subject_id = pe.subject_id AND icu.hadm_id = pe.hadm_id AND icu.stay_id = pe.stay_id
  WHERE
    pe.starttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR)
  GROUP BY
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
), CohortStats AS (
  SELECT
    AVG(distinct_procedures) AS avg_distinct_procedures,
    PERCENTILE_CONT(0.75, distinct_procedures) AS p75_distinct_procedures,
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS avg_mortality
  FROM ProceduresInFirst72Hours
), AgeMatchedCohort AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    ic.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON p.subject_id = ic.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
), AgeMatchedStats AS (
  SELECT
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS avg_mortality
  FROM AgeMatchedCohort
)
SELECT
  cs.avg_distinct_procedures,
  cs.p75_distinct_procedures,
  cs.avg_icu_los,
  cs.avg_mortality,
  ams.avg_icu_los AS age_matched_avg_icu_los,
  ams.avg_mortality AS age_matched_avg_mortality
FROM CohortStats AS cs, AgeMatchedStats AS ams;