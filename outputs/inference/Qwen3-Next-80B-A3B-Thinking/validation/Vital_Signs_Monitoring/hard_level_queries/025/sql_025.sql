WITH cardiac_arrest_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON d.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON d.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON d.hadm_id = a.hadm_id
  WHERE 
    (d.icd_version = 9 AND d.icd_code = '427.5')
    OR (d.icd_version = 10 AND d.icd_code IN ('I46.0', 'I46.1', 'I46.2', 'I46.8', 'I46.9'))
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
),
bp_ranges AS (
  SELECT 
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    MAX(e.valuenum) - MIN(e.valuenum) AS systolic_range
  FROM cardiac_arrest_patients c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` e 
    ON c.stay_id = e.stay_id
    AND e.itemid = 220050  -- Systolic BP
    AND e.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND e.valuenum IS NOT NULL
  GROUP BY c.stay_id, c.los, c.hospital_expire_flag
),
top_decile_threshold AS (
  SELECT 
    PERCENTILE_CONT(systolic_range, 0.9) WITHIN GROUP (ORDER BY systolic_range) AS threshold
  FROM bp_ranges
)
SELECT 
  (COUNT(CASE WHEN b.systolic_range <= 70 THEN 1 END) * 100.0 / COUNT(*)) AS percentile_of_70,
  AVG(CASE WHEN b.systolic_range >= t.threshold THEN b.los ELSE NULL END) AS mean_los_top_decile,
  AVG(CASE WHEN b.systolic_range >= t.threshold THEN b.hospital_expire_flag ELSE NULL END) AS mortality_rate_top_decile
FROM bp_ranges b
CROSS JOIN top_decile_threshold t;