WITH shock_cohort AS (
  SELECT i.stay_id,
         i.subject_id,
         i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON i.subject_id = di.subject_id AND i.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 60 AND 70
    AND LOWER(ddi.long_title) LIKE '%mixed shock%'
),

instability_score AS (
  SELECT
    sc.stay_id,
    sc.subject_id,
    sc.hadm_id,
    COALESCE(SUM(CASE WHEN LOWER(di.label) LIKE '%heart rate%' AND ce.valuenum > 100 THEN 1 ELSE 0 END), 0)
    + COALESCE(SUM(CASE WHEN LOWER(di.label) LIKE '%mean arterial pressure%' AND ce.valuenum < 65 THEN 1 ELSE 0 END), 0) AS instability_score
  FROM shock_cohort sc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON i.stay_id = sc.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = sc.stay_id
   AND ce.hadm_id = sc.hadm_id
   AND ce.charttime >= i.intime
   AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = ce.itemid
  GROUP BY sc.stay_id, sc.subject_id, sc.hadm_id
),

hypot_flags AS (
  SELECT sc.stay_id,
         MAX(CASE WHEN LOWER(di.label) LIKE '%mean arterial pressure%' AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS hypot_flag
  FROM shock_cohort sc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON i.stay_id = sc.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = sc.stay_id
   AND ce.hadm_id = sc.hadm_id
   AND ce.charttime >= i.intime
   AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = ce.itemid
  GROUP BY sc.stay_id
),

tach_flags AS (
  SELECT sc.stay_id,
         MAX(CASE WHEN LOWER(di.label) LIKE '%heart rate%' AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tach_flag
  FROM shock_cohort sc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON i.stay_id = sc.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = sc.stay_id
   AND ce.hadm_id = sc.hadm_id
   AND ce.charttime >= i.intime
   AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = ce.itemid
  GROUP BY sc.stay_id
),

mortality AS (
  SELECT sc.stay_id,
         MAX(CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END) AS mortality_flag
  FROM shock_cohort sc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON sc.hadm_id = a.hadm_id
  GROUP BY sc.stay_id
),

icu_los AS (
  SELECT sc.stay_id, i.los AS icu_los
  FROM shock_cohort sc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON sc.stay_id = i.stay_id
),

all_stays AS (
  SELECT sc.stay_id, sc.subject_id, sc.hadm_id,
         COALESCE(iscore.instability_score, 0) AS instability_score
  FROM shock_cohort sc
  LEFT JOIN instability_score AS iscore
    ON sc.stay_id = iscore.stay_id
),

merged AS (
  SELECT a.stay_id,
         a.subject_id,
         a.hadm_id,
         a.instability_score,
         COALESCE(hf.hypot_flag, 0) AS hypot_flag,
         COALESCE(tf.tach_flag, 0) AS tach_flag,
         COALESCE(mortality.mortality_flag, 0) AS mortality_flag,
         COALESCE(il.icu_los, 0) AS icu_los
  FROM all_stays a
  LEFT JOIN hypot_flags AS hf ON a.stay_id = hf.stay_id
  LEFT JOIN tach_flags AS tf ON a.stay_id = tf.stay_id
  LEFT JOIN mortality AS mortality ON a.stay_id = mortality.stay_id
  LEFT JOIN icu_los AS il ON a.stay_id = il.stay_id
),

p95 AS (
  SELECT quantiles[OFFSET(95)] AS p95
  FROM (SELECT APPROX_QUANTILES(instability_score, 100) AS quantiles
        FROM all_stays) AS t
),

scored AS (
  SELECT m.*,
         CASE WHEN m.instability_score >= p95.p95 THEN 1 ELSE 0 END AS is_top_decile
  FROM merged m CROSS JOIN p95
),

metrics AS (
  SELECT is_top_decile,
         COUNT(*) AS n_stays,
         AVG(hypot_flag) AS hypot_rate,
         AVG(tach_flag) AS tach_rate,
         (
           SELECT quantiles[OFFSET(50)]
           FROM (
             SELECT APPROX_QUANTILES(icu_los, 100) AS quantiles
             FROM scored s2
             WHERE s2.is_top_decile = scored.is_top_decile
           )
         ) AS median_icu_los,
         AVG(mortality_flag) AS mortality_rate
  FROM scored
  GROUP BY is_top_decile
  ORDER BY is_top_decile
)
SELECT *
FROM metrics;