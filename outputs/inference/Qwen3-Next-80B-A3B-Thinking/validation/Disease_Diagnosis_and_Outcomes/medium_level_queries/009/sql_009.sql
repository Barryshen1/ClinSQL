WITH sepsis_admissions AS (
  SELECT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.hadm_id
  HAVING 
    MAX(CASE 
      WHEN (d.icd_version = 9 AND (d.icd_code LIKE '038%' OR d.icd_code IN ('99591', '99592'))) 
        OR (d.icd_version = 10 AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%')) 
      THEN 1 ELSE 0 
    END) = 1
    AND
    MAX(CASE 
      WHEN (d.icd_version = 9 AND d.icd_code = '78552') 
        OR (d.icd_version = 10 AND d.icd_code = 'R6521') 
      THEN 1 ELSE 0 
    END) = 0
),
filtered_admissions AS (
  SELECT a.*, 
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
      WHERE i.hadm_id = a.hadm_id 
        AND i.intime <= a.admittime + INTERVAL 24 HOUR
    ) THEN 1 ELSE 0 END AS icu_day1
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN sepsis_admissions s ON a.hadm_id = s.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 53 AND 63
),
mech_vent_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%ventilator%' OR label LIKE '%mechanical ventilation%'
),
vasopressor_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%norepinephrine%' 
    OR label LIKE '%vasopressin%' 
    OR label LIKE '%epinephrine%' 
    OR label LIKE '%dopamine%' 
    OR label LIKE '%phenylephrine%'
),
rrt_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%dialysis%' 
    OR label LIKE '%RRT%' 
    OR label LIKE '%renal replacement therapy%'
),
mech_vent_flags AS (
  SELECT p.hadm_id, 1 AS mech_vent
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN mech_vent_itemids m ON p.itemid = m.itemid
  GROUP BY p.hadm_id
),
vasopressor_flags AS (
  SELECT i.hadm_id, 1 AS vasopressor
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  JOIN vasopressor_itemids v ON i.itemid = v.itemid
  GROUP BY i.hadm_id
),
rrt_flags AS (
  SELECT p.hadm_id, 1 AS rrt
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN rrt_itemids r ON p.itemid = r.itemid
  GROUP BY p.hadm_id
)
SELECT 
  CASE WHEN los < 8 THEN '<8' ELSE '>=8' END AS los_category,
  icu_day1,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(COALESCE(mech_vent, 0)) * 100 AS mech_vent_pct,
  AVG(COALESCE(vasopressor, 0)) * 100 AS vasopressor_pct,
  AVG(COALESCE(rrt, 0)) * 100 AS rrt_pct
FROM (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    m.mech_vent,
    v.vasopressor,
    r.rrt,
    a.icu_day1
  FROM filtered_admissions a
  LEFT JOIN mech_vent_flags m ON a.hadm_id = m.hadm_id
  LEFT JOIN vasopressor_flags v ON a.hadm_id = v.hadm_id
  LEFT JOIN rrt_flags r ON a.hadm_id = r.hadm_id
) sub
GROUP BY los_category, icu_day1;