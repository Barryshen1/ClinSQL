WITH first_icu AS (
  SELECT *
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
  QUALIFY ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime ASC) = 1
),
patients AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M' AND anchor_age BETWEEN 53 AND 63
),
admissions AS (
  SELECT hadm_id, admittime, hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions
),
sepsis_adm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  WHERE icd_version = 10
    AND (icd_code = 'R65.20' OR icd_code LIKE 'A41.%')
    AND hadm_id NOT IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
      WHERE icd_code = 'R65.21' AND icd_version = 10
    )
),
cohort AS (
  SELECT 
    f.stay_id, f.subject_id, f.hadm_id, f.intime, f.los,
    a.admittime, a.hospital_expire_flag,
    CASE WHEN DATE(f.intime) = DATE(a.admittime) THEN 1 ELSE 0 END AS day1_icu,
    CASE WHEN f.los < 8 THEN '<8' ELSE '>=8' END AS los_group
  FROM first_icu f
  INNER JOIN patients p ON f.subject_id = p.subject_id
  INNER JOIN admissions a ON f.hadm_id = a.hadm_id
  INNER JOIN sepsis_adm s ON f.hadm_id = s.hadm_id
),
vent_items AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE itemid IN (720, 223848, 223849, 224009, 224138, 224176, 224182, 224512, 228099, 228269, 228280, 228284, 225477, 225681)
),
mech_vent AS (
  SELECT DISTINCT stay_id
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN vent_items v ON ce.itemid = v.itemid
  WHERE ce.value IS NOT NULL
),
vaso_items AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%norepinephrine%' OR LOWER(label) LIKE '%noradrenaline%'
     OR LOWER(label) LIKE '%dopamine%'
     OR LOWER(label) LIKE '%epinephrine%'
     OR LOWER(label) LIKE '%phenylephrine%'
     OR LOWER(label) LIKE '%vasopressin%'
),
vaso AS (
  SELECT DISTINCT stay_id
  FROM `physionet-data.mimiciv_3_1_icu`.inputevents ie
  INNER JOIN vaso_items vi ON ie.itemid = vi.itemid
  WHERE (ie.amount IS NOT NULL AND ie.amount > 0) OR (ie.rate IS NOT NULL AND ie.rate > 0)
),
rrt_items AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%dialysis%' OR LOWER(label) LIKE '%rrt%' OR LOWER(label) LIKE '%cvvh%'
     OR LOWER(label) LIKE '%cvvhd%' OR LOWER(label) LIKE '%cvvhdf%' OR LOWER(label) LIKE '%hemodia%'
     OR LOWER(label) LIKE '%ultrafiltration%' OR LOWER(label) LIKE '%hemofiltration%'
),
rrt AS (
  SELECT DISTINCT stay_id
  FROM `physionet-data.mimiciv_3_1_icu`.procedureevents pe
  INNER JOIN rrt_items ri ON pe.itemid = ri.itemid
  WHERE pe.starttime IS NOT NULL
)
SELECT 
  los_group,
  day1_icu,
  COUNT(DISTINCT hadm_id) AS n,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN mv.stay_id IS NOT NULL THEN hadm_id END) / COUNT(DISTINCT hadm_id), 2) AS mech_vent_pct,
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN va.stay_id IS NOT NULL THEN hadm_id END) / COUNT(DISTINCT hadm_id), 2) AS vasopressors_pct,
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN rr.stay_id IS NOT NULL THEN hadm_id END) / COUNT(DISTINCT hadm_id), 2) AS rrt_pct
FROM cohort c
LEFT JOIN mech_vent mv ON c.stay_id = mv.stay_id
LEFT JOIN vaso va ON c.stay_id = va.stay_id
LEFT JOIN rrt rr ON c.stay_id = rr.stay_id
GROUP BY los_group, day1_icu
ORDER BY los_group, day1_icu;