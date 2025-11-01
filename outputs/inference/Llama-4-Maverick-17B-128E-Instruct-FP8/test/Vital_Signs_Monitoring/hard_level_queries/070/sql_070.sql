WITH 
hhs_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
  ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE diag.long_title LIKE '%Hyperosmolar hyperglycemic state%' AND d.icd_version = 10
),
vital_signs AS (
  SELECT c.hadm_id, c.stay_id, c.itemid, c.charttime, c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` i ON c.itemid = i.itemid
  WHERE i.label IN ('Heart Rate', 'Mean Arterial Pressure', 'Respiratory Rate')
),
cv_calculations AS (
  SELECT stay_id, 
         itemid,
         CASE 
           WHEN COUNT(valuenum) < 2 THEN NULL
           ELSE STDDEV(valuenum) / NULLIF(AVG(valuenum), 0)
         END AS cv
  FROM vital_signs
  WHERE charttime BETWEEN (SELECT MIN(intime) FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = vital_signs.stay_id) 
                      AND TIMESTAMP_ADD((SELECT MIN(intime) FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = vital_signs.stay_id), INTERVAL 24 HOUR)
  GROUP BY stay_id, itemid
),
cv_sum AS (
  SELECT stay_id, 
         SUM(cv) AS total_cv
  FROM cv_calculations
  WHERE cv IS NOT NULL
  GROUP BY stay_id
  HAVING COUNT(cv) = 3  -- Ensure all three vital signs are present
),
top_quartile AS (
  SELECT stay_id, total_cv,
         PERCENT_RANK() OVER (ORDER BY total_cv DESC) AS percentile
  FROM cv_sum
),
combined_data AS (
  SELECT p.subject_id, p.gender, p.anchor_age,
         i.stay_id, i.hadm_id, i.intime, i.outtime, i.los,
         a.hospital_expire_flag,
         cv.total_cv,
         t.percentile
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  JOIN hhs_patients h ON i.hadm_id = h.hadm_id
  JOIN cv_sum cv ON i.stay_id = cv.stay_id
  JOIN top_quartile t ON cv.stay_id = t.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 78 AND 88
)
SELECT 
  AVG(total_cv) AS avg_cv,
  'Top Quartile' AS instability_decile,
  AVG(los) AS avg_icu_los,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate
FROM combined_data
WHERE percentile <= 0.25;