WITH vent_itemids AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%ventilat%' 
     OR LOWER(label) LIKE '%intubat%'
),
vasopressor_itemids AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%norepinephrine%'
     OR LOWER(label) LIKE '%dopamine%'
     OR LOWER(label) LIKE '%epinephrine%'
     OR LOWER(label) LIKE '%phenylephrine%'
     OR LOWER(label) LIKE '%vasopressin%'
     OR LOWER(label) LIKE '%dobutamine%'
),
rrt_itemids AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%dialysis%'
     OR LOWER(label) LIKE '%rrt%'
     OR LOWER(label) LIKE '%hemodialysis%'
     OR LOWER(label) LIKE '%crrt%'
),
cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND a.dischtime IS NOT NULL
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 79 AND 89
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE (icd_code IN ('J13','J14','J15','J16','J18','J690') AND icd_version = 10)
         OR (icd_code IN ('481','482','483','485','486','5070') AND icd_version = 9)
    )
),
cohort_with_icu AS (
  SELECT 
    c.*,
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = c.hadm_id
        AND i.intime <= TIMESTAMP_ADD(c.admittime, INTERVAL '1' DAY)
    ) THEN 1 ELSE 0 END AS day1_icu
  FROM cohort c
),
mech_vent AS (
  SELECT hadm_id, 1 AS mech_vent_flag
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE itemid IN (SELECT itemid FROM vent_itemids)
  GROUP BY hadm_id
),
vasopressors AS (
  SELECT hadm_id, 1 AS vasopressor_flag
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE itemid IN (SELECT itemid FROM vasopressor_itemids)
  GROUP BY hadm_id
),
rrt AS (
  SELECT hadm_id, 1 AS rrt_flag
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE itemid IN (SELECT itemid FROM rrt_itemids)
  GROUP BY hadm_id
)
SELECT
  CASE WHEN hospital_los <= 7 THEN '≤7' ELSE '>7' END AS los_group,
  CASE WHEN day1_icu = 1 THEN 'Yes' ELSE 'No' END AS day1_icu,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate_percent,
  SUM(COALESCE(mech_vent_flag, 0)) AS mech_vent_count,
  ROUND(SUM(COALESCE(mech_vent_flag, 0)) * 100.0 / COUNT(*), 2) AS mech_vent_rate_percent,
  SUM(COALESCE(vasopressor_flag, 0)) AS vasopressor_count,
  ROUND(SUM(COALESCE(vasopressor_flag, 0)) * 100.0 / COUNT(*), 2) AS vasopressor_rate_percent,
  SUM(COALESCE(rrt_flag, 0)) AS rrt_count,
  ROUND(SUM(COALESCE(rrt_flag, 0)) * 100.0 / COUNT(*), 2) AS rrt_rate_percent
FROM cohort_with_icu
LEFT JOIN mech_vent USING (hadm_id)
LEFT JOIN vasopressors USING (hadm_id)
LEFT JOIN rrt USING (hadm_id)
GROUP BY los_group, day1_icu
ORDER BY los_group, day1_icu;