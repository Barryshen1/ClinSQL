WITH 
-- Step 1: Identify patients with acute ischemic stroke
stroke_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_year, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 78 AND 88
    AND dicd.long_title LIKE '%Acute ischemic stroke%'
),

-- Step 2: Calculate minimum 72-hour laboratory instability score
lab_instability AS (
  SELECT sp.hadm_id, 
         COUNT(CASE WHEN le.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE label IN ('Creatinine', 'Potassium', 'Sodium', 'White Blood Cell Count')) 
                    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR) THEN 1 ELSE NULL END) AS critical_lab_count
  FROM stroke_patients sp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON sp.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON sp.hadm_id = le.hadm_id
  GROUP BY sp.hadm_id
),

-- Step 3 & 4: Compare critical lab events and report cohort LOS and in-hospital mortality
cohort_outcomes AS (
  SELECT 
    sp.hadm_id,
    li.critical_lab_count,
    a.dischtime - a.admittime AS los,
    a.hospital_expire_flag AS in_hospital_mortality
  FROM stroke_patients sp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON sp.hadm_id = a.hadm_id
  LEFT JOIN lab_instability li ON sp.hadm_id = li.hadm_id
)

-- Final query to get required statistics
SELECT 
  MIN(li.critical_lab_count) AS min_72hr_lab_instability,
  AVG(li.critical_lab_count) AS avg_critical_lab_events_cohort,
  (SELECT AVG(critical_lab_count) FROM lab_instability WHERE hadm_id NOT IN (SELECT hadm_id FROM stroke_patients)) AS avg_critical_lab_events_general,
  AVG(co.los) AS avg_los,
  SUM(co.in_hospital_mortality) / COUNT(co.hadm_id) AS in_hospital_mortality_rate
FROM cohort_outcomes co
LEFT JOIN lab_instability li ON co.hadm_id = li.hadm_id;