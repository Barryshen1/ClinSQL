WITH ich_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    -- match diagnosis text for intracerebral hemorrhage (covers ICD-9/ICD-10 textual titles)
    AND LOWER(dd.long_title) LIKE '%intracerebral%hemorrhag%'
),

-- Abnormal lab counts (distinct lab labels) within first 48 hours of admission
abnormal_labs_48h AS (
  SELECT
    ia.hadm_id,
    COUNT(DISTINCT dl.label) AS instability_score
  FROM ich_admissions ia
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ia.hadm_id = le.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE le.charttime >= ia.admittime
    AND le.charttime <= TIMESTAMP_ADD(ia.admittime, INTERVAL 48 HOUR)
    AND le.flag IS NOT NULL
    AND TRIM(le.flag) != ''
  GROUP BY ia.hadm_id
),

-- Baseline cohort with scores, LOS, mortality, ICU flag
cohort_with_scores AS (
  SELECT
    ia.hadm_id,
    ia.subject_id,
    ia.admittime,
    ia.dischtime,
    ia.hospital_expire_flag,
    ia.anchor_age,
    ia.gender,
    COALESCE(al.instability_score, 0) AS instability_score,
    -- LOS in days as fractional days
    SAFE_DIVIDE(CAST(TIMESTAMP_DIFF(ia.dischtime, ia.admittime, SECOND) AS FLOAT64), 86400.0) AS los_days,
    -- has ICU stay during this admission?
    CASE WHEN icu.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_icustay
  FROM ich_admissions ia
  LEFT JOIN abnormal_labs_48h al
    ON ia.hadm_id = al.hadm_id
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
    ON ia.hadm_id = icu.hadm_id
),

-- Assign quartiles using NTILE(4) over instability_score (Q1 = lowest scores)
cohort_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM cohort_with_scores
),

-- Aggregate cohort results by quartile
quartile_summary AS (
  SELECT
    quartile,
    COUNT(*) AS n_admissions,
    ROUND(AVG(los_days), 3) AS mean_los_days,
    ROUND(100.0 * AVG(hospital_expire_flag), 2) AS mortality_pct,
    ROUND(100.0 * AVG(has_icustay), 2) AS icu_transfer_pct
  FROM cohort_quartiles
  GROUP BY quartile
  ORDER BY quartile
),

-- Overall ICU transfer (critical care) rate among all inpatients (all hospital admissions)
overall_icu_rate AS (
  SELECT
    ROUND(100.0 * SAFE_DIVIDE(COUNT(DISTINCT icu.hadm_id), COUNT(DISTINCT a.hadm_id)), 2) AS overall_icu_transfer_pct
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
    ON a.hadm_id = icu.hadm_id
)

-- Final: quartile summaries with comparison to overall inpatients' ICU transfer rate
SELECT
  q.quartile,
  q.n_admissions,
  q.mean_los_days,
  q.mortality_pct,
  q.icu_transfer_pct,
  o.overall_icu_transfer_pct,
  -- relative ICU transfer rate (quartile / overall)
  ROUND(SAFE_DIVIDE(q.icu_transfer_pct, NULLIF(o.overall_icu_transfer_pct, 0)), 3) AS icu_rate_vs_all_ratio
FROM quartile_summary q
CROSS JOIN overall_icu_rate o
ORDER BY q.quartile;