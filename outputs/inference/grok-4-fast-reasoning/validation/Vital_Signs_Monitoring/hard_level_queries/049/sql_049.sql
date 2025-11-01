WITH icu_first AS (
  SELECT *
  FROM (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      first_careunit,
      last_careunit,
      intime,
      outtime,
      los,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),
cohort AS (
  SELECT DISTINCT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year AS age
  FROM icu_first i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND dd.long_title LIKE '%sepsis%'
    AND p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year BETWEEN 78 AND 88
),
instability AS (
  SELECT 
    co.stay_id,
    MAX(ce.valuenum) AS instability_score  -- Max in first 24h; assumes higher = more unstable
  FROM cohort co
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = co.subject_id
    AND ce.hadm_id = co.hadm_id
    AND ce.stay_id = co.stay_id
    AND ce.charttime BETWEEN co.intime AND TIMESTAMP_ADD(co.intime, INTERVAL 24 HOUR)
    AND ce.itemid = 220045  -- PLACEHOLDER: Replace with actual itemid for 'instability score' from d_items (e.g., if charted; otherwise, compute via SOFA/vitals aggregation)
    AND ce.valuenum IS NOT NULL
  GROUP BY co.stay_id
),
full_data AS (
  SELECT 
    co.*,
    ins.instability_score
  FROM cohort co
  LEFT JOIN instability ins
    ON co.stay_id = ins.stay_id
  WHERE ins.instability_score IS NOT NULL  -- Exclude stays without score
),
with_quartile AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS quartile  -- Q4 = highest scores
  FROM full_data
)
SELECT 
  (SELECT COUNTIF(instability_score <= 85) * 100.0 / COUNT(*) FROM full_data) AS percentile_rank_85,
  (SELECT AVG(los) FROM with_quartile WHERE quartile = 4) AS mean_icu_los_q4,
  (SELECT AVG(hospital_expire_flag) FROM with_quartile WHERE quartile = 4) AS hospital_mortality_q4;