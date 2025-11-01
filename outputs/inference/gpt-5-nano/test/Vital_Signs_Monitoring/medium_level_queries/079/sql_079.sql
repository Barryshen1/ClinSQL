WITH cohort AS (
  SELECT
    i.hadm_id,
    i.stay_id,
    p.subject_id,
    AVG(ce.valuenum) AS mean_sbp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = i.subject_id
   AND ce.hadm_id = i.hadm_id
   AND ce.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ce.itemid
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND ce.charttime >= i.intime
    AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
    -- Capture SBP: common patterns for systolic BP entries
    AND REGEXP_CONTAINS(LOWER(di.label), r'systolic.*blood.*pressure|blood.*pressure.*systolic|systolic')
    AND ce.valuenum IS NOT NULL
  GROUP BY i.hadm_id, i.stay_id, p.subject_id
),
sbp_by_stay AS (
  SELECT
    hadm_id,
    stay_id,
    subject_id,
    mean_sbp,
    CASE
      WHEN mean_sbp < 140 THEN '<140'
      WHEN mean_sbp BETWEEN 140 AND 159 THEN '140-159'
      WHEN mean_sbp >= 160 THEN '>=160'
    END AS sbp_cat
  FROM cohort
  WHERE mean_sbp IS NOT NULL
),
mi_per_hadm AS (
  -- MI per admission (hadm_id) via diagnoses_icd joined to long_title
  SELECT di.hadm_id, 1 AS mi_any
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%myocardial infarction%'
  GROUP BY di.hadm_id
),
joined AS (
  SELECT s.hadm_id, s.stay_id, s.subject_id, s.sbp_cat, COALESCE(m.mi_any, 0) AS mi_flag
  FROM sbp_by_stay s
  LEFT JOIN mi_per_hadm m ON s.hadm_id = m.hadm_id
),
stats AS (
  SELECT sbp_cat, COUNT(*) AS total_stays, SUM(mi_flag) AS mi_events
  FROM joined
  GROUP BY sbp_cat
),
tot AS (
  SELECT SUM(total_stays) AS grand_total FROM stats
),
final AS (
  SELECT s.sbp_cat,
         s.total_stays,
         s.mi_events,
         ROUND(100.0 * s.total_stays / (SELECT grand_total FROM tot), 2) AS percent_in_category
  FROM stats s
)
SELECT
  f.sbp_cat,
  f.total_stays,
  f.mi_events,
  f.percent_in_category,
  ROUND(100.0 * f.mi_events / NULLIF(f.total_stays, 0), 2) AS mi_rate_per_category
FROM final f
ORDER BY f.sbp_cat;