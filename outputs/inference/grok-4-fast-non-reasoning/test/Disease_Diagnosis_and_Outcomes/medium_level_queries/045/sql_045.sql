WITH cohort AS (
  -- Base cohort: women 79-89 with pneumonia
  SELECT DISTINCT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.admission_type != 'NEWBORN'
    AND REGEXP_CONTAINS(LOWER(d.icd_code), r'(?i)^(j1[8-9]|j15|j16|j17|j18|j69|486|5070)')  -- ICD-10: J15-J18/J69; ICD-9: 486 (pneumonia), 5070 (aspiration)
    AND a.hadm_id IS NOT NULL
    AND icd.icd_version IS NOT NULL
),

day1_icu AS (
  -- Flag admissions with day-1 ICU
  SELECT 
    t.hadm_id,
    1 AS has_day1_icu
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.transfers` t
    ON a.hadm_id = t.hadm_id
  WHERE t.eventtype = 'admit'
    AND t.careunit IN ('SICU', 'MICU', 'CCU', 'CSRU', 'TSICU', 'NICU')
    AND DATE(t.intime) <= DATE_ADD(DATE(a.admittime), INTERVAL 1 DAY)
),

mech_vent AS (
  -- Mechanical ventilation (any in any ICU stay)
  SELECT DISTINCT 
    ie.hadm_id,
    1 AS has_mech_vent
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  WHERE ce.itemid IN (720, 223848, 223849, 224008, 224031, 225477, 225478, 225479,
                      225916, 221912, 222315, 227589)
    AND ce.value IS NOT NULL
    AND (ce.valuenum > 0 OR ce.value != '0')
    AND ce.charttime BETWEEN ie.intime AND ie.outtime
),

vasopressor AS (
  -- Vasopressors (any in any ICU stay)
  SELECT DISTINCT 
    ie.hadm_id,
    1 AS has_vaso
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` inp
    ON ie.stay_id = inp.stay_id
  WHERE inp.itemid IN (220615, 221906, 223835, 225798, 227481, 225159, 221289, 222282,
                       225468, 225442)
    AND inp.amount > 0
    AND inp.starttime BETWEEN ie.intime AND ie.outtime
),

rrt AS (
  -- RRT (any in any ICU stay)
  SELECT DISTINCT 
    ie.hadm_id,
    1 AS has_rrt
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` inp
    ON ie.stay_id = inp.stay_id
    AND inp.itemid IN (225826, 225830, 225831, 225832, 225833, 225834,
                       228369)
    AND inp.amount > 0
    AND inp.starttime BETWEEN ie.intime AND ie.outtime
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON ie.stay_id = pe.stay_id
    AND pe.itemid IN (225456)
    AND pe.value IS NOT NULL
    AND pe.starttime BETWEEN ie.intime AND ie.outtime
  WHERE inp.stay_id IS NOT NULL OR pe.stay_id IS NOT NULL
)

-- Main aggregation
SELECT 
  CASE WHEN c.los_days <= 7 THEN 'LOS <=7 days' ELSE 'LOS >7 days' END AS los_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(c.hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(COALESCE(d1.has_day1_icu, 0)) * 100, 2) AS day1_icu_pct,
  ROUND(AVG(COALESCE(mv.has_mech_vent, 0)) * 100, 2) AS mech_vent_pct,
  ROUND(AVG(COALESCE(va.has_vaso, 0)) * 100, 2) AS vasopressor_pct,
  ROUND(AVG(COALESCE(rr.has_rrt, 0)) * 100, 2) AS rrt_pct
FROM cohort c
LEFT JOIN day1_icu d1 ON c.hadm_id = d1.hadm_id
LEFT JOIN mech_vent mv ON c.hadm_id = mv.hadm_id
LEFT JOIN vasopressor va ON c.hadm_id = va.hadm_id
LEFT JOIN rrt rr ON c.hadm_id = rr.hadm_id
GROUP BY los_group
ORDER BY 
  CASE los_group WHEN 'LOS <=7 days' THEN 1 ELSE 2 END;