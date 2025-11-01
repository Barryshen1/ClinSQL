WITH pneumonia_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    (icd_version = 10 AND icd_code IN ('J13', 'J14', 'J15', 'J18', 'J69.0'))
  )
),
cohort AS (
  SELECT DISTINCT adm.hadm_id, p.subject_id, p.anchor_age,
    adm.admittime, adm.dischtime, adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN pneumonia_codes pc
    ON diag.icd_code = pc.icd_code AND diag.icd_version = 10
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
),
icu_day1 AS (
  SELECT DISTINCT i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE DATETIME_DIFF(i.intime, a.admittime, HOUR) <= 24
    AND i.intime >= a.admittime
),
mech_vent AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ventilat%'
    OR LOWER(ordercategoryname) LIKE '%ventilat%'
    OR LOWER(ordercategorydescription) LIKE '%ventilat%'
),
vasopressors AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  WHERE LOWER(ordercategoryname) = 'vasopressor'
),
rrt AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%dialysis%'
     OR LOWER(di.label) LIKE '%crrt%'
     OR LOWER(ordercategoryname) LIKE '%dialysis%'
)

SELECT
  CASE WHEN c.los_days <= 7 THEN '≤7 days' ELSE '>7 days' END AS los_group,
  COUNT(*) AS n_patients,
  AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
  AVG(CAST(i1.hadm_id IS NOT NULL AS INT64)) AS icu_day1_rate,
  AVG(CAST(mv.hadm_id IS NOT NULL AS INT64)) AS mech_vent_rate,
  AVG(CAST(vs.hadm_id IS NOT NULL AS INT64)) AS vasopressor_rate,
  AVG(CAST(rt.hadm_id IS NOT NULL AS INT64)) AS rrt_rate
FROM cohort c
LEFT JOIN icu_day1 i1 ON c.hadm_id = i1.hadm_id
LEFT JOIN mech_vent mv ON c.hadm_id = mv.hadm_id
LEFT JOIN vasopressors vs ON c.hadm_id = vs.hadm_id
LEFT JOIN rrt rt ON c.hadm_id = rt.hadm_id
GROUP BY los_group
ORDER BY los_group;