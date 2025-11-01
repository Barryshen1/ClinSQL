WITH cardiac_arrest_cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,  -- Added to expose ICU admission time
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND (
      (d.icd_version = 9 AND d.icd_code = '4275') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I46.%')
    )
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 55 AND 65
),
instability_scores AS (
  SELECT 
    c.stay_id,
    STDDEV(ce.valuenum) AS instability_score
  FROM cardiac_arrest_cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid = 220045  -- Heart rate itemid
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)  -- Fixed reference to c.intime
    AND ce.valuenum IS NOT NULL
  GROUP BY c.stay_id
  HAVING COUNT(ce.valuenum) >= 5  -- Require minimum measurements
),
cohort_analysis AS (
  SELECT 
    cs.*,
    i.los,
    a.hospital_expire_flag,
    NTILE(10) OVER (ORDER BY cs.instability_score DESC) AS instability_decile
  FROM instability_scores cs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON cs.stay_id = i.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
)
SELECT 
  (SELECT COUNT(*) FROM cohort_analysis WHERE instability_score <= 70) * 100.0 / COUNT(*) AS percentile_70,
  AVG(IF(instability_decile = 1, los, NULL)) AS mean_los_top_decile,
  AVG(IF(instability_decile = 1, hospital_expire_flag, NULL)) AS mortality_top_decile
FROM cohort_analysis;