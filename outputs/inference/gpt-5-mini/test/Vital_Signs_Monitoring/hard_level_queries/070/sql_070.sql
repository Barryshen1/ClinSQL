WITH
-- 1) cohort of ICU stays for male patients age 78-88 with an HHS diagnosis on the same admission
hhs_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%hyperosmolar%'
),
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.anchor_age,
    p.gender,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND icu.hadm_id IN (SELECT hadm_id FROM hhs_admissions)
),

-- 2) Aggregate vitals (HR, MAP, RR) for the first 24 hours of each ICU stay
vitals_24h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.los AS icu_los,
    c.hospital_expire_flag,
    -- Heart rate stats
    AVG(CASE WHEN LOWER(di.label) LIKE '%heart rate%' THEN ce.valuenum END) AS hr_mean,
    STDDEV_SAMP(CASE WHEN LOWER(di.label) LIKE '%heart rate%' THEN ce.valuenum END) AS hr_sd,
    MAX(CASE WHEN LOWER(di.label) LIKE '%heart rate%' AND (ce.valuenum < 60 OR ce.valuenum > 100) THEN 1 ELSE 0 END) AS hr_abn_flag,
    -- MAP stats (mean arterial pressure)
    AVG(CASE WHEN (LOWER(di.label) LIKE '%mean arterial%' OR LOWER(di.label) LIKE '%map%') THEN ce.valuenum END) AS map_mean,
    STDDEV_SAMP(CASE WHEN (LOWER(di.label) LIKE '%mean arterial%' OR LOWER(di.label) LIKE '%map%') THEN ce.valuenum END) AS map_sd,
    MAX(CASE WHEN (LOWER(di.label) LIKE '%mean arterial%' OR LOWER(di.label) LIKE '%map%')
             AND (ce.valuenum < 65 OR ce.valuenum > 110) THEN 1 ELSE 0 END) AS map_abn_flag,
    -- Respiratory rate stats
    AVG(CASE WHEN LOWER(di.label) LIKE '%respiratory rate%' THEN ce.valuenum END) AS rr_mean,
    STDDEV_SAMP(CASE WHEN LOWER(di.label) LIKE '%respiratory rate%' THEN ce.valuenum END) AS rr_sd,
    MAX(CASE WHEN LOWER(di.label) LIKE '%respiratory rate%' AND (ce.valuenum < 12 OR ce.valuenum > 20) THEN 1 ELSE 0 END) AS rr_abn_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = c.stay_id
   AND ce.subject_id = c.subject_id
   AND ce.charttime >= c.intime
   AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    -- limit to relevant labels in the WHERE to avoid excessive aggregation on unrelated items
    AND (
         LOWER(di.label) LIKE '%heart rate%'
      OR LOWER(di.label) LIKE '%respiratory rate%'
      OR LOWER(di.label) LIKE '%mean arterial%'
      OR LOWER(di.label) LIKE '%map%'
    )
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id, c.intime, c.outtime, c.los, c.hospital_expire_flag
),

-- 3) Compute CVs, instability_score, and abnormal_vital_count
per_stay_scores AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    -- CVs: stddev / mean, coalesced to 0 if null
    COALESCE(SAFE_DIVIDE(v.hr_sd, v.hr_mean), 0.0) AS hr_cv,
    COALESCE(SAFE_DIVIDE(v.map_sd, v.map_mean), 0.0) AS map_cv,
    COALESCE(SAFE_DIVIDE(v.rr_sd, v.rr_mean), 0.0) AS rr_cv,
    -- Instability score = sum of the three CVs
    (COALESCE(SAFE_DIVIDE(v.hr_sd, v.hr_mean), 0.0)
     + COALESCE(SAFE_DIVIDE(v.map_sd, v.map_mean), 0.0)
     + COALESCE(SAFE_DIVIDE(v.rr_sd, v.rr_mean), 0.0)) AS instability_score,
    -- count of abnormal vitals in first 24h (0-3)
    (COALESCE(v.hr_abn_flag, 0) + COALESCE(v.map_abn_flag, 0) + COALESCE(v.rr_abn_flag, 0)) AS abnormal_vital_count,
    v.icu_los,
    v.hospital_expire_flag
  FROM vitals_24h v
),

-- 4) compute the 75th percentile threshold for instability_score (top quartile)
p75 AS (
  SELECT
    (APPROX_QUANTILES(instability_score, 4))[OFFSET(3)] AS p75_value
  FROM per_stay_scores
  WHERE instability_score IS NOT NULL
),

-- 5) Add deciles (1 = lowest instability, 10 = highest)
with_deciles AS (
  SELECT
    ps.*,
    NTILE(10) OVER (ORDER BY instability_score) AS decile
  FROM per_stay_scores ps
)

-- Final selection: stays in the top quartile by instability_score
SELECT
  wd.subject_id,
  wd.hadm_id,
  wd.stay_id,
  ROUND(wd.instability_score, 6) AS instability_score,
  wd.decile,
  wd.abnormal_vital_count,
  wd.icu_los,
  wd.hospital_expire_flag AS in_hospital_mortality
FROM with_deciles wd
CROSS JOIN p75
WHERE wd.instability_score >= p75.p75_value
ORDER BY wd.instability_score DESC, wd.stay_id
;