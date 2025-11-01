WITH patients_cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 79 AND 89
),
admissions_with_pneumonia AS (
  SELECT a.*
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_cohort p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE d.icd_version = 10
    AND (d.icd_code LIKE 'J12%' OR d.icd_code LIKE 'J13%' OR d.icd_code LIKE 'J15%' OR d.icd_code LIKE 'J16%' OR d.icd_code LIKE 'J18%' OR d.icd_code = 'J690')
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.deathtime, a.admission_type, a.admit_provider_id, a.admission_location, a.discharge_location, a.insurance, a.language, a.marital_status, a.race, a.edregtime, a.edouttime, a.hospital_expire_flag
),
admissions_with_los AS (
  SELECT 
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) <= 7 THEN '≤7' ELSE '>7' END AS los_category
  FROM admissions_with_pneumonia
),
admissions_with_icu AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.los_category,
    a.hospital_expire_flag,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = a.hadm_id
        AND TIMESTAMP_DIFF(i.intime, a.admittime, HOUR) <= 24
    ) THEN 1 ELSE 0 END AS day_1_icu
  FROM admissions_with_los a
),
mech_vent_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE category = 'Respiratory'
    AND label LIKE '%ventilator%'
),
mech_vent_admissions AS (
  SELECT DISTINCT i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON c.stay_id = i.stay_id
  WHERE c.itemid IN (SELECT itemid FROM mech_vent_itemids)
    AND c.charttime BETWEEN i.intime AND i.outtime
),
vasopressor_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE category = 'Medication'
    AND (label LIKE '%norepinephrine%' 
         OR label LIKE '%epinephrine%' 
         OR label LIKE '%dopamine%' 
         OR label LIKE '%vasopressor%')
),
vasopressor_admissions AS (
  SELECT DISTINCT i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` inpt
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON inpt.stay_id = i.stay_id
  WHERE inpt.itemid IN (SELECT itemid FROM vasopressor_itemids)
    AND inpt.starttime BETWEEN i.intime AND i.outtime
),
rrt_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE category = 'Medication'
    AND (label LIKE '%dialysis%' 
         OR label LIKE '%CRRT%' 
         OR label LIKE '%renal replacement%')
),
rrt_admissions AS (
  SELECT DISTINCT i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` inpt
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON inpt.stay_id = i.stay_id
  WHERE inpt.itemid IN (SELECT itemid FROM rrt_itemids)
    AND inpt.starttime BETWEEN i.intime AND i.outtime
)
SELECT 
  los_category,
  day_1_icu,
  COUNT(*) AS num_admissions,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(mech_vent) AS mech_vent_prevalence,
  AVG(vasopressor) AS vasopressor_prevalence,
  AVG(rrt) AS rrt_prevalence
FROM (
  SELECT 
    a.hadm_id,
    a.los_category,
    a.day_1_icu,
    a.hospital_expire_flag,
    CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS mech_vent,
    CASE WHEN vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS vasopressor,
    CASE WHEN rr.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS rrt
  FROM admissions_with_icu a
  LEFT JOIN mech_vent_admissions mv ON a.hadm_id = mv.hadm_id
  LEFT JOIN vasopressor_admissions vp ON a.hadm_id = vp.hadm_id
  LEFT JOIN rrt_admissions rr ON a.hadm_id = rr.hadm_id
)
GROUP BY los_category, day_1_icu
ORDER BY los_category, day_1_icu;