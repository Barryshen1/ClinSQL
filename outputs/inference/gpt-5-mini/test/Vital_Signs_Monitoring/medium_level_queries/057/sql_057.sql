WITH temp_chart AS (
  -- Select temperature chart events for male patients aged 85-95, convert to Celsius
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    ce.valuenum AS raw_valuenum,
    LOWER(COALESCE(ce.valueuom, di.unitname, '')) AS unit_norm,
    CASE
      WHEN LOWER(COALESCE(ce.valueuom, di.unitname, '')) LIKE '%f%' THEN (ce.valuenum - 32.0) * 5.0/9.0
      ELSE ce.valuenum
    END AS temp_c
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id
    AND ce.hadm_id = icu.hadm_id
    AND ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE
    -- identify temperature-related items by label/abbreviation
    (LOWER(di.label) LIKE '%temperature%' OR LOWER(di.abbreviation) LIKE '%temp%')
    AND ce.valuenum IS NOT NULL
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
),

per_stay_avg AS (
  -- Compute per-stay average temperature in Celsius, only keeping plausible temps
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    AVG(temp_c) AS avg_temp_c,
    COUNT(*) AS n_temps
  FROM temp_chart
  WHERE temp_c BETWEEN 25.0 AND 45.0
  GROUP BY subject_id, hadm_id, stay_id
)

SELECT
  (SELECT COUNT(*) FROM per_stay_avg WHERE avg_temp_c <= 36.0) AS n_stays_leq_36_0,
  (SELECT COUNT(*) FROM per_stay_avg) AS total_stays_considered,
  ROUND(
    100.0 * (SELECT COUNT(*) FROM per_stay_avg WHERE avg_temp_c <= 36.0)
    / NULLIF((SELECT COUNT(*) FROM per_stay_avg), 0),
    2
  ) AS percentile_rank_pct_of_36_0
;