WITH ARDS_Patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND d.icd_code = 'J80' -- ARDS ICD-10 code
), ICU_Stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN ARDS_Patients AS ap
    ON s.subject_id = ap.subject_id
    AND s.hadm_id = ap.hadm_id
), Procedures_First_24h AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedures
  FROM ICU_Stays AS ic
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON ic.subject_id = pe.subject_id
    AND ic.hadm_id = pe.hadm_id
    AND ic.stay_id = pe.stay_id
  WHERE
    pe.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 24 HOUR)
  GROUP BY
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id
), ARDS_Stats AS (
  SELECT
    PERCENTILE_CONT(distinct_procedures, 0.25) AS p25_procedures,
    PERCENTILE_CONT(distinct_procedures, 0.75) AS p75_procedures,
    PERCENTILE_CONT(distinct_procedures, 0.95) AS p95_procedures,
    AVG(los) AS avg_los,
    AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality
  FROM Procedures_First_24h AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
    AND p.hadm_id = a.hadm_id
), General_ICU_Stats AS (
  SELECT
    PERCENTILE_CONT(distinct_procedures, 0.25) AS p25_procedures,
    PERCENTILE_CONT(distinct_procedures, 0.75) AS p75_procedures,
    PERCENTILE_CONT(distinct_procedures, 0.95) AS p95_procedures,
    AVG(los) AS avg_los,
    AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS s
    ON pe.subject_id = s.subject_id
    AND pe.hadm_id = s.hadm_id
    AND pe.stay_id = s.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON s.subject_id = a.subject_id
    AND s.hadm_id = a.hadm_id
  WHERE
    pe.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
)
SELECT
  'ARDS Patients (84-94)' AS cohort,
  ARDS_Stats.p25_procedures,
  ARDS_Stats.p75_procedures,
  ARDS_Stats.p95_procedures,
  ARDS_Stats.avg_los,
  ARDS_Stats.mortality;