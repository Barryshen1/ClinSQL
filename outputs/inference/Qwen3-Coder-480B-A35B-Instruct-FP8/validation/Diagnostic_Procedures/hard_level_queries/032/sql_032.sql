WITH age_filtered_patients AS (
  SELECT p.subject_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.anchor_age BETWEEN 66 AND 76
    AND p.gender = 'F'
),

first_icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN age_filtered_patients p ON i.subject_id = p.subject_id
  WHERE i.intime = (
    SELECT MIN(intime)
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i2
    WHERE i2.subject_id = i.subject_id
  )
),

sepsis_patients AS (
  SELECT DISTINCT f.subject_id, f.hadm_id, f.stay_id
  FROM first_icu_stays f
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON f.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
),

procedures_in_48h AS (
  SELECT pe.subject_id, pe.hadm_id, pe.stay_id, COUNT(DISTINCT pe.itemid) AS proc_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN first_icu_stays f
    ON pe.stay_id = f.stay_id
  WHERE pe.starttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 48 HOUR)
  GROUP BY pe.subject_id, pe.hadm_id, pe.stay_id
),

sepsis_procedures AS (
  SELECT s.subject_id, s.hadm_id, s.stay_id, COALESCE(p.proc_count, 0) AS proc_count
  FROM sepsis_patients s
  LEFT JOIN procedures_in_48h p
    ON s.stay_id = p.stay_id
),

non_sepsis_controls AS (
  SELECT f.subject_id, f.hadm_id, f.stay_id
  FROM first_icu_stays f
  LEFT JOIN sepsis_patients s
    ON f.subject_id = s.subject_id
  WHERE s.subject_id IS NULL
),

non_sepsis_procedures AS (
  SELECT f.subject_id, f.hadm_id, f.stay_id, COALESCE(p.proc_count, 0) AS proc_count
  FROM non_sepsis_controls f
  LEFT JOIN procedures_in_48h p
    ON f.stay_id = p.stay_id
),

sepsis_stats AS (
  SELECT
    APPROX_QUANTILES(proc_count, 100)[OFFSET(90)] AS p90_procedures,
    AVG(DATETIME_DIFF(a.dischtime, a.admittime, HOUR)) AS avg_los,
    AVG(a.hospital_expire_flag) AS mortality_rate
  FROM sepsis_procedures s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
),

non_sepsis_stats AS (
  SELECT
    AVG(DATETIME_DIFF(a.dischtime, a.admittime, HOUR)) AS avg_los,
    AVG(a.hospital_expire_flag) AS mortality_rate
  FROM non_sepsis_procedures n
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON n.hadm_id = a.hadm_id
)

SELECT
  s.p90_procedures,
  s.avg_los AS sepsis_avg_los,
  s.mortality_rate AS sepsis_mortality,
  n.avg_los AS control_avg_los,
  n.mortality_rate AS control_mortality
FROM sepsis_stats s
CROSS JOIN non_sepsis_stats n;