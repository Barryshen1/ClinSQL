WITH injury_counts AS (
  SELECT 
    hadm_id,
    COUNT(*) AS num_injuries
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
  WHERE 
    (icd_version = 10 AND icd_code >= 'S00' AND icd_code <= 'T88')
    OR 
    (icd_version = 9 AND icd_code >= '800' AND icd_code < '960')
  GROUP BY hadm_id
  HAVING num_injuries >= 2
),
cohort_stays AS (
  SELECT 
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON s.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON s.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),
first_stays AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime ASC) AS rn
  FROM cohort_stays
),
valid_stays AS (
  SELECT fs.*
  FROM first_stays fs
  INNER JOIN injury_counts ic 
    ON fs.hadm_id = ic.hadm_id
  WHERE rn = 1
),
abnormal_vitals AS (
  SELECT 
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.itemid,
    ce.valuenum,
    CASE 
      WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1
      WHEN ce.itemid = 220179 AND ce.valuenum < 90 THEN 1
      WHEN ce.itemid = 220210 AND ce.valuenum > 20 THEN 1
      ELSE 0 
    END AS abnormal
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN valid_stays vs 
    ON ce.subject_id = vs.subject_id 
    AND ce.hadm_id = vs.hadm_id 
    AND ce.stay_id = vs.stay_id
  WHERE ce.itemid IN (220045, 220179, 220210)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= vs.intime
    AND ce.charttime < TIMESTAMP_ADD(vs.intime, INTERVAL 1 DAY)
),
stay_scores AS (
  SELECT 
    stay_id,
    SUM(abnormal) AS instability_score,
    SUM(CASE WHEN itemid = 220045 AND abnormal = 1 THEN 1 ELSE 0 END) AS tachycardia_count,
    SUM(CASE WHEN itemid = 220179 AND abnormal = 1 THEN 1 ELSE 0 END) AS hypotension_count,
    SUM(CASE WHEN itemid = 220210 AND abnormal = 1 THEN 1 ELSE 0 END) AS tachypnea_count
  FROM abnormal_vitals
  GROUP BY stay_id
),
cohort_with_scores AS (
  SELECT 
    vs.stay_id,
    vs.los,
    vs.hospital_expire_flag,
    COALESCE(ss.instability_score, 0) AS instability_score,
    COALESCE(ss.tachycardia_count, 0) AS tachycardia_count,
    COALESCE(ss.hypotension_count, 0) AS hypotension_count,
    COALESCE(ss.tachypnea_count, 0) AS tachypnea_count
  FROM valid_stays vs
  LEFT JOIN stay_scores ss 
    ON vs.stay_id = ss.stay_id
)
-- Top decile details
SELECT 
  ROUND(AVG(tachycardia_count), 2) AS mean_tachycardia_episodes,
  ROUND(AVG(hypotension_count), 2) AS mean_hypotension_episodes,
  ROUND(AVG(tachypnea_count), 2) AS mean_tachypnea_episodes
FROM (
  SELECT *,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile_rank
  FROM cohort_with_scores
)
WHERE decile_rank = 1;