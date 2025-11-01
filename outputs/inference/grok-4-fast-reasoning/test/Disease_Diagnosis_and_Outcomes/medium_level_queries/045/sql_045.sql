WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag AS mortality,
    CASE WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 7 THEN '<=7' ELSE '>7' END AS los_group
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.admission_location = 'EMERGENCY ROOM'
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '480%' OR d.icd_code LIKE '481%' OR d.icd_code LIKE '482%' OR d.icd_code LIKE '483%' OR d.icd_code LIKE '484%' OR d.icd_code LIKE '485%' OR d.icd_code LIKE '486%' OR d.icd_code = '507.0'))
      OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'J12%' OR d.icd_code LIKE 'J13%' OR d.icd_code LIKE 'J14%' OR d.icd_code LIKE 'J15%' OR d.icd_code LIKE 'J16%' OR d.icd_code LIKE 'J17%' OR d.icd_code LIKE 'J18%' OR d.icd_code LIKE 'J69%' OR d.icd_code = 'J70.0'))
    )
),
first_icu AS (
  SELECT 
    subject_id,
    hadm_id,
    intime AS first_intime,
    stay_id AS first_stay_id
  FROM (
    SELECT 
      subject_id,
      hadm_id,
      intime,
      stay_id,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime ASC) AS rn
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),
mech_vent_first24 AS (
  SELECT DISTINCT
    ce.stay_id,
    1 AS has_mech_vent
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i ON ce.stay_id = i.stay_id
  WHERE 
    ce.itemid IN (720, 148687, 223848, 223849, 224009, 224139, 224328, 224631, 224985, 227041, 227042, 227043, 227044, 227045)
    AND ce.charttime >= i.intime
    AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 1 DAY)
),
vaso_first24 AS (
  SELECT DISTINCT
    ie.stay_id,
    1 AS has_vaso
  FROM 
    `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i ON ie.stay_id = i.stay_id
  WHERE 
    ie.itemid IN (220592, 220603, 220615, 221906, 222315, 223258, 30047)
    AND ie.starttime >= i.intime
    AND ie.starttime < TIMESTAMP_ADD(i.intime, INTERVAL 1 DAY)
    AND ie.rateuom IS NOT NULL
    AND ie.rate > 0
),
rrt_first24 AS (
  SELECT DISTINCT
    pe.stay_id,
    1 AS has_rrt
  FROM 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i ON pe.stay_id = i.stay_id
  WHERE 
    pe.itemid IN (225490, 225826, 228537)
    AND pe.starttime >= i.intime
    AND pe.starttime < TIMESTAMP_ADD(i.intime, INTERVAL 1 DAY)
)
SELECT 
  los_group,
  icu_day1,
  COUNT(*) AS n_patients,
  SUM(mortality) AS num_deaths,
  ROUND(SAFE_DIVIDE(SUM(mortality), COUNT(*)) * 100, 2) AS mortality_pct,
  ROUND(AVG(mech_vent) * 100, 2) AS mech_vent_prevalence_pct,
  ROUND(AVG(vasopressor) * 100, 2) AS vasopressor_prevalence_pct,
  ROUND(AVG(rrt) * 100, 2) AS rrt_prevalence_pct
FROM (
  SELECT 
    c.los_group,
    c.mortality,
    CASE 
      WHEN fi.first_intime IS NULL OR fi.first_intime > TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY) 
      THEN 0 
      ELSE 1 
    END AS icu_day1,
    CASE 
      WHEN fi.first_intime IS NULL OR fi.first_intime > TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY) 
      THEN 0
      ELSE COALESCE(mv.has_mech_vent, 0)
    END AS mech_vent,
    CASE 
      WHEN fi.first_intime IS NULL OR fi.first_intime > TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY) 
      THEN 0
      ELSE COALESCE(va.has_vaso, 0)
    END AS vasopressor,
    CASE 
      WHEN fi.first_intime IS NULL OR fi.first_intime > TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY) 
      THEN 0
      ELSE COALESCE(rr.has_rrt, 0)
    END AS rrt
  FROM 
    cohort c
  LEFT JOIN 
    first_icu fi ON c.subject_id = fi.subject_id AND c.hadm_id = fi.hadm_id
  LEFT JOIN 
    mech_vent_first24 mv ON fi.first_stay_id = mv.stay_id
  LEFT JOIN 
    vaso_first24 va ON fi.first_stay_id = va.stay_id
  LEFT JOIN 
    rrt_first24 rr ON fi.first_stay_id = rr.stay_id
)
GROUP BY los_group, icu_day1
ORDER BY los_group, icu_day1;