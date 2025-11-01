WITH
-- 1. Identify UGIB diagnosis codes
ugib_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%upper gastrointestinal%' 
    OR LOWER(long_title) LIKE '%UGIB%' 
    OR LOWER(long_title) LIKE '%upper GI bleed%'
),

-- 2. Cohort: male, age 60-70, with UGIB, ICU stay
ugib_icustays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id
   AND icu.hadm_id    = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON icu.subject_id = d.subject_id
   AND icu.hadm_id    = d.hadm_id
  JOIN ugib_codes uc
    ON d.icd_code      = uc.icd_code
   AND d.icd_version   = uc.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
),

-- 3. Lookup itemids for HR, MAP, RR
vital_items AS (
  SELECT
    MAX(CASE WHEN LOWER(label) LIKE '%heart rate%'        THEN itemid END) AS hr_id,
    MAX(CASE WHEN LOWER(label) LIKE '%mean arterial%'     THEN itemid END) AS map_id,
    MAX(CASE WHEN LOWER(label) LIKE '%respiratory rate%'  THEN itemid END) AS rr_id
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
),

-- 4. Extract first 48h vital events and flag instability
vitals_48h AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    v.itemid,
    v.valuenum,
    CASE WHEN v.itemid = vi.hr_id  AND v.valuenum > 100 THEN 1 ELSE 0 END AS tachy,
    CASE WHEN v.itemid = vi.map_id AND v.valuenum < 65  THEN 1 ELSE 0 END AS hypo,
    CASE WHEN v.itemid = vi.rr_id  AND v.valuenum > 20  THEN 1 ELSE 0 END AS tachyp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` v
  CROSS JOIN vital_items vi
  JOIN ugib_icustays u
    ON v.subject_id = u.subject_id
   AND v.hadm_id    = u.hadm_id
   AND v.stay_id    = u.stay_id
  WHERE v.charttime BETWEEN u.intime AND TIMESTAMP_ADD(u.intime, INTERVAL 48 HOUR)
    AND v.valuenum IS NOT NULL
    AND v.itemid IN (vi.hr_id, vi.map_id, vi.rr_id)
),

-- 5. Compute per-stay instability index and any-event flags
instability_by_stay AS (
  SELECT
    stay_id,
    SUM(tachy + hypo + tachyp) AS instability_index,
    MAX(tachy)   AS any_tachy,
    MAX(hypo)    AS any_hypo,
    MAX(tachyp)  AS any_tachyp
  FROM vitals_48h
  GROUP BY stay_id
),

-- 6. Attach index & events back to cohort
cohort_with_index AS (
  SELECT
    u.*,
    ibs.instability_index,
    ibs.any_tachy,
    ibs.any_hypo,
    ibs.any_tachyp
  FROM ugib_icustays u
  LEFT JOIN instability_by_stay ibs
    ON u.stay_id = ibs.stay_id
),

-- 7. Compute 90th and 95th percentiles of the index
percentiles AS (
  SELECT
    APPROX_QUANTILES(instability_index, 100)[OFFSET(90)] AS p90,
    APPROX_QUANTILES(instability_index, 100)[OFFSET(95)] AS p95
  FROM cohort_with_index
  WHERE instability_index IS NOT NULL
),

-- 8. Tag top‐decile vs controls
labeled_cohort AS (
  SELECT
    c.*,
    p.p90,
    p.p95,
    CASE
      WHEN c.instability_index >= p.p90 THEN 'top_decile'
      ELSE 'control'
    END AS group_label
  FROM cohort_with_index c
  CROSS JOIN percentiles p
)

-- 9. Final aggregation: overall 95th percentile + group comparisons
SELECT
  -- 95th percentile of the instability index
  p.p95 AS instability_index_95th_percentile,
  
  -- Metrics by group
  lc.group_label,
  COUNT(*)                                    AS n_patients,
  ROUND(AVG(any_tachy)*100,2)   AS pct_tachycardia,
  ROUND(AVG(any_hypo)*100,2)    AS pct_MAP_lt_65,
  ROUND(AVG(any_tachyp)*100,2)  AS pct_tachypnea,
  ROUND(AVG(lc.los),2)          AS mean_icu_los_days,
  ROUND(AVG(lc.hospital_expire_flag)*100,2) AS pct_hospital_mortality
FROM labeled_cohort lc
CROSS JOIN percentiles p
GROUP BY group_label, p.p95
ORDER BY group_label;