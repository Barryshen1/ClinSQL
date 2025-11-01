WITH sbp_items_events AS (
  -- Select systolic BP measurements from chartevents using d_items text matching
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE (
      LOWER(di.label) LIKE '%systolic%'    -- capture labels that mention systolic
      OR LOWER(di.abbreviation) LIKE '%sys%' -- capture abbreviations
    )
    -- prefer mmHg units where available (valueuom may be null for some rows)
    AND (
      LOWER(COALESCE(ce.valueuom, di.unitname, '')) LIKE '%mmhg%'
      OR di.unitname IS NOT NULL
    )
    AND ce.valuenum IS NOT NULL
    -- reasonable physiologic bounds for systolic BP
    AND ce.valuenum BETWEEN 30 AND 300
),

stay_avg_sbp AS (
  -- Compute per-stay average SBP within first 24 hours of ICU admission
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    AVG(se.valuenum) AS avg_sbp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN sbp_items_events se
    ON se.stay_id = icu.stay_id
   AND se.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
),

filtered_stay_avgs AS (
  -- Keep only female patients aged 45-55
  SELECT
    s.subject_id,
    s.stay_id,
    s.avg_sbp
  FROM stay_avg_sbp s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
)

-- Final aggregation: count distinct patients per SBP category.
SELECT
  category,
  COUNT(DISTINCT subject_id) AS unique_patient_count,
  COUNT(*) AS num_stays_in_category
FROM (
  SELECT
    subject_id,
    stay_id,
    avg_sbp,
    CASE
      WHEN avg_sbp < 140 THEN '<140'
      WHEN avg_sbp >= 140 AND avg_sbp < 160 THEN '140-159'
      ELSE '>=160'
    END AS category
  FROM filtered_stay_avgs
)
GROUP BY category
ORDER BY
  CASE category WHEN '<140' THEN 1 WHEN '140-159' THEN 2 ELSE 3 END;