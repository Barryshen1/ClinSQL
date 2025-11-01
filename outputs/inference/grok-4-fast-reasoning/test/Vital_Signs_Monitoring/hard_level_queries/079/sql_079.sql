WITH qualifying_stays AS (
  -- Select qualifying ICU stays: male, 81-91yo, with HFNC in first 48h
  SELECT DISTINCT
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` h
      WHERE h.stay_id = i.stay_id
        AND h.itemid = 223848  -- O2 device
        AND LOWER(h.value) LIKE '%high flow%'
        AND h.charttime >= i.intime
        AND h.charttime <= i.intime + INTERVAL 48 HOUR
    )
),
with_scores AS (
  -- Compute max FiO2 (proxy for instability score) in first 48h
  SELECT
    qs.*,
    MAX(ce.valuenum) AS score
  FROM qualifying_stays qs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON qs.stay_id = ce.stay_id
    AND ce.itemid = 223835  -- FiO2
    AND ce.charttime >= qs.intime
    AND ce.charttime <= qs.intime + INTERVAL 48 HOUR
    AND ce.valuenum IS NOT NULL
  GROUP BY
    qs.stay_id, qs.subject_id, qs.hadm_id, qs.intime, qs.los, qs.hospital_expire_flag
)
-- Final aggregates: percentile for score=85, top decile stats
SELECT
  (SUM(CASE WHEN score <= 85 THEN 1.0 ELSE 0.0 END) / COUNT(*) * 100) AS percentile_for_85,
  AVG(CASE WHEN ntile = 1 THEN los END) AS avg_los_top_decile_days,
  (AVG(CASE WHEN ntile = 1 THEN hospital_expire_flag END) * 100) AS hospital_mortality_top_decile_pct
FROM (
  SELECT *, NTILE(10) OVER (ORDER BY score DESC) AS ntile
  FROM with_scores
  WHERE score IS NOT NULL  -- Exclude stays without FiO2 measurement
);