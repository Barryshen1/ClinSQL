WITH 
filtered_admissions AS (
  SELECT a.hadm_id, p.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 71 AND 81
),
hosp_los AS (
  SELECT hadm_id, DATETIME_DIFF(dischtime, admittime, HOUR) AS los,
         hospital_expire_flag,
         CASE WHEN hadm_id IN (SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`) THEN 'ICU' ELSE 'Non-ICU' END AS icu_status
  FROM filtered_admissions
),
los_quartiles AS (
  SELECT icu_status, 
         APPROX_QUANTILES(los, 4) AS los_quartiles
  FROM hosp_los
  GROUP BY icu_status
),
los_quartile_assignment AS (
  SELECT h.hadm_id, h.los, h.icu_status, h.hospital_expire_flag,
         CASE 
           WHEN h.los <= l.los_quartiles[OFFSET(1)] THEN 'Q1'
           WHEN h.los <= l.los_quartiles[OFFSET(2)] THEN 'Q2'
           WHEN h.los <= l.los_quartiles[OFFSET(3)] THEN 'Q3'
           ELSE 'Q4'
         END AS los_quartile
  FROM hosp_los h
  JOIN los_quartiles l ON h.icu_status = l.icu_status
),
treatments AS (
  SELECT i.hadm_id, 
         MAX(CASE WHEN di.label LIKE '%Vent%' THEN 1 ELSE 0 END) AS mech_vent,
         MAX(CASE WHEN di.label LIKE '%Vasopressor%' THEN 1 ELSE 0 END) AS vasopressor,
         MAX(CASE WHEN di.label LIKE '%RRT%' OR di.label LIKE '%Dialysis%' THEN 1 ELSE 0 END) AS rrt
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON i.itemid = di.itemid
  GROUP BY i.hadm_id
),
combined_data AS (
  SELECT l.hadm_id, l.icu_status, l.los_quartile, l.hospital_expire_flag,
         t.mech_vent, t.vasopressor, t.rrt
  FROM los_quartile_assignment l
  LEFT JOIN treatments t ON l.hadm_id = t.hadm_id
)
SELECT 
  icu_status,
  los_quartile,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS in_hospital_mortality,
  AVG(mech_vent) * 100 AS perc_mech_vent,
  AVG(vasopressor) * 100 AS perc_vasopressor,
  AVG(rrt) * 100 AS perc_rrt
FROM combined_data
GROUP BY icu_status, los_quartile
ORDER BY icu_status, los_quartile;