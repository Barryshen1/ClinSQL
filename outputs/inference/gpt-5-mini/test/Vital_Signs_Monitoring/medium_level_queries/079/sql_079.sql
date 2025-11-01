WITH sbp_items AS (
  -- identify SBP-related itemids in ICU d_items by label
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
),

sbp_vals AS (
  -- SBP measurements (numeric) from chartevents for those itemids
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN sbp_items di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
),

sbp_first48 AS (
  -- per-stay mean SBP during first 48 hours of the ICU stay
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    AVG(sf.valuenum) AS mean_sbp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN sbp_vals sf
    ON sf.stay_id = s.stay_id
   AND sf.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
  GROUP BY s.subject_id, s.hadm_id, s.stay_id
),

mi_hadm AS (
  -- flag hospital admissions that include any diagnosis with "myocardial infarction" in the description
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code
   AND d.icd_version = icd.icd_version
  WHERE LOWER(icd.long_title) LIKE '%myocardial infarction%'
),

cohort AS (
  -- restrict to male patients aged 40-50 (anchor_age) and include per-stay mean SBP
  SELECT s.*, p.gender, p.anchor_age
  FROM sbp_first48 s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),

cohort_with_mi AS (
  -- attach MI flag and SBP category per stay
  SELECT
    c.*,
    CASE WHEN m.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS mi_flag,
    CASE
      WHEN c.mean_sbp < 140 THEN '<140'
      WHEN c.mean_sbp >= 140 AND c.mean_sbp < 160 THEN '140-159'
      ELSE '>=160'
    END AS sbp_category
  FROM cohort c
  LEFT JOIN mi_hadm m
    ON c.hadm_id = m.hadm_id
),

agg AS (
  SELECT
    sbp_category,
    COUNT(*) AS n_stays,
    SUM(mi_flag) AS mi_count
  FROM cohort_with_mi
  GROUP BY sbp_category
),

total AS (
  SELECT COUNT(*) AS total_stays FROM cohort_with_mi
)

SELECT
  a.sbp_category,
  a.n_stays,
  ROUND(100.0 * SAFE_DIVIDE(a.n_stays, t.total_stays), 2) AS percent_of_cohort,
  a.mi_count,
  ROUND(100.0 * SAFE_DIVIDE(a.mi_count, a.n_stays), 2) AS mi_rate_percent
FROM agg a
CROSS JOIN total t
ORDER BY
  CASE
    WHEN a.sbp_category = '<140' THEN 1
    WHEN a.sbp_category = '140-159' THEN 2
    WHEN a.sbp_category = '>=160' THEN 3
    ELSE 4
  END;