WITH dka_patients AS (
  SELECT DISTINCT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ketoacidosis%'
),
patient_info AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 39 AND 49
),
dka_filtered AS (
  SELECT pi.*
  FROM patient_info pi
  JOIN dka_patients dk
    ON pi.subject_id = dk.subject_id
),
first_icu_stay AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN dka_filtered d
    ON i.subject_id = d.subject_id
),
first_stay AS (
  SELECT *
  FROM first_icu_stay
  WHERE rn = 1
),
procedures_24h AS (
  SELECT
    f.stay_id,
    COUNT(DISTINCT p.itemid) AS procedure_count
  FROM first_stay f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON f.stay_id = p.stay_id
    AND p.starttime >= f.intime
    AND p.starttime < DATETIME_ADD(f.intime, INTERVAL 24 HOUR)
  GROUP BY f.stay_id
),
quintiles AS (
  SELECT
    stay_id,
    procedure_count,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM procedures_24h
)
SELECT
  q.quintile,
  COUNT(*) AS num_stays,
  AVG(q.procedure_count) AS mean_procedure_count,
  MIN(q.procedure_count) AS min_procedure_count,
  MAX(q.procedure_count) AS max_procedure_count,
  AVG(f.los) AS mean_icu_los_days,
  AVG(a.hospital_expire_flag) AS hospital_mortality_rate
FROM quintiles q
JOIN first_stay f ON q.stay_id = f.stay_id
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON f.hadm_id = a.hadm_id
GROUP BY q.quintile
ORDER BY q.quintile;