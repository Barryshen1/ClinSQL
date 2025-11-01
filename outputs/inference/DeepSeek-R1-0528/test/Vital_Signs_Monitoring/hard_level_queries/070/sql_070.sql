WITH hhs_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '2502%') OR
    (icd_version = 10 AND icd_code IN ('E1100', 'E1101'))
),

cohort_stays AS (
  SELECT 
    p.subject_id, 
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN hhs_admissions h
    ON i.hadm_id = h.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 78 AND 88
),

vitals AS (
  SELECT 
    c.stay_id,
    ce.itemid,
    ce.valuenum
  FROM cohort_stays c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE 
    ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.itemid IN (220045, 220181, 220210)  -- HR, MAP, RR
    AND ce.valuenum IS NOT NULL
),

cv_calculation AS (
  SELECT 
    stay_id,
    AVG(CASE WHEN itemid = 220045 THEN valuenum END) AS mean_hr,
    STDDEV(CASE WHEN itemid = 220045 THEN valuenum END) AS std_hr,
    AVG(CASE WHEN itemid = 220181 THEN valuenum END) AS mean_map,
    STDDEV(CASE WHEN itemid = 220181 THEN valuenum END) AS std_map,
    AVG(CASE WHEN itemid = 220210 THEN valuenum END) AS mean_rr,
    STDDEV(CASE WHEN itemid = 220210 THEN valuenum END) AS std_rr,
    MAX(CASE WHEN itemid = 220045 AND (valuenum < 60 OR valuenum > 100) THEN 1 ELSE 0 END) AS hr_abnormal,
    MAX(CASE WHEN itemid = 220181 AND (valuenum < 70 OR valuenum > 100) THEN 1 ELSE 0 END) AS map_abnormal,
    MAX(CASE WHEN itemid = 220210 AND (valuenum < 12 OR valuenum > 20) THEN 1 ELSE 0 END) AS rr_abnormal
  FROM vitals
  GROUP BY stay_id
  HAVING 
    mean_hr IS NOT NULL AND std_hr IS NOT NULL AND
    mean_map IS NOT NULL AND std_map IS NOT NULL AND
    mean_rr IS NOT NULL AND std_rr IS NOT NULL
),

cv_sum_data AS (
  SELECT 
    stay_id,
    (std_hr / mean_hr) + (std_map / mean_map) + (std_rr / mean_rr) AS cv_sum,
    hr_abnormal + map_abnormal + rr_abnormal AS abnormal_vital_count
  FROM cv_calculation
),

cv_ranks AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY cv_sum) AS quartile,
    NTILE(10) OVER (ORDER BY cv_sum) AS decile
  FROM cv_sum_data
)

SELECT 
  c.stay_id,
  r.cv_sum AS stay_instability_score,
  r.decile,
  r.abnormal_vital_count,
  c.los AS icu_los,
  c.hospital_expire_flag AS in_hospital_mortality
FROM cv_ranks r
INNER JOIN cohort_stays c
  ON r.stay_id = c.stay_id
WHERE r.quartile = 4
ORDER BY r.cv_sum DESC;