WITH 
-- Step 1: Identify sepsis patients
sepsis_patients AS (
  SELECT DISTINCT h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON h.icd_code = d.icd_code AND h.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Sepsis%' AND h.icd_version = 10
),

-- Step 2: Filter patients based on age, gender, and admission details
filtered_patients AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 53 AND 63
  AND a.hadm_id IN (SELECT hadm_id FROM sepsis_patients)
),

-- Step 3: Determine ICU stay details
icu_stays AS (
  SELECT i.hadm_id, i.stay_id, i.intime, i.outtime, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN filtered_patients f
  ON i.hadm_id = f.hadm_id
),

-- Step 4: Identify treatments on the first day of ICU stay
day1_treatments AS (
  SELECT i.hadm_id, 
         MAX(CASE WHEN d.label LIKE '%Mechanical Vent%' THEN 1 ELSE 0 END) AS mech_vent,
         MAX(CASE WHEN d.label LIKE '%Vasopressor%' THEN 1 ELSE 0 END) AS vasopressor,
         MAX(CASE WHEN d.label LIKE '%RRT%' OR d.label LIKE '%CRRT%' THEN 1 ELSE 0 END) AS rrt
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN icu_stays i ON c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  WHERE c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 1 DAY)
  GROUP BY i.hadm_id
),

-- Step 5: Calculate in-hospital mortality and LOS stratification
outcomes AS (
  SELECT a.hadm_id, 
         a.hospital_expire_flag AS mortality,
         CASE WHEN i.los < 8 THEN '<8' ELSE '>=8' END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN icu_stays i ON a.hadm_id = i.hadm_id
)

-- Final aggregation
SELECT o.los_group,
       COUNT(CASE WHEN o.mortality = 1 THEN 1 END) / COUNT(*) * 100 AS in_hospital_mortality,
       SUM(t.mech_vent) / COUNT(*) * 100 AS mech_vent_prevalence,
       SUM(t.vasopressor) / COUNT(*) * 100 AS vasopressor_prevalence,
       SUM(t.rrt) / COUNT(*) * 100 AS rrt_prevalence
FROM outcomes o
LEFT JOIN day1_treatments t ON o.hadm_id = t.hadm_id
GROUP BY o.los_group;