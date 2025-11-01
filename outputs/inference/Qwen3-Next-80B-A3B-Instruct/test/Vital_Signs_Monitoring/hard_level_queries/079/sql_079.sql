WITH hfnc_procedure AS (
  SELECT di.itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items` di
  WHERE LOWER(di.label) LIKE '%hfnc%'
     OR LOWER(di.label) LIKE '%high flow%'
     OR LOWER(di.label) LIKE '%high flow nasal%'
  AND di.linksto = 'procedureevents'
),
cohort AS (
  SELECT DISTINCT
    i.subject_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.stay_id = pe.stay_id
  INNER JOIN hfnc_procedure hp
    ON pe.itemid = hp.itemid
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND pe.starttime >= i.intime
    AND pe.starttime <= DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
)
SELECT
  AVG(los) AS avg_icu_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS hospital_mortality_percent
FROM cohort;