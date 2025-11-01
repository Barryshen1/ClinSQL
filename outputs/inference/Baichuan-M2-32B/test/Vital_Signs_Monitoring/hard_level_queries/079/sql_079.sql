WITH eligible_icu AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    p.gender,
    -- Compute age at ICU admission: anchor_age + (current ICU year - anchor_year)
    (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 81 AND 91
),
hfnc_admin AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    MAX(starttime) AS hfnc_time  -- at least one HFNC event in first 48h
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` 
  WHERE 
    itemid = 227488  -- Placeholder; verify with: SELECT * FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%HFNC%' OR label LIKE '%High-Flow%'
    AND starttime BETWEEN 
        (SELECT intime FROM eligible_icu e WHERE e.subject_id = inputevents.subject_id AND e.hadm_id = inputevents.hadm_id) 
        AND (SELECT intime FROM eligible_icu e WHERE e.subject_id = inputevents.subject_id AND e.hadm_id = inputevents.hadm_id) + INTERVAL 48 HOUR
  GROUP BY subject_id, hadm_id, stay_id
),
composite_score AS (
  SELECT 
    o.subject_id,
    o.hadm_id,
    MAX(CAST(o.result_value AS FLOAT64)) AS composite_score  -- Assuming result_value is numeric string; adjust if needed
  FROM `physionet-data.mimiciv_3_1_hosp.omr` o
  INNER JOIN eligible_icu e
    ON o.subject_id = e.subject_id AND o.hadm_id = e.hadm_id
  WHERE 
    o.result_name = 'Composite Instability Score'  -- Verify existence in omr
    AND o.chartdate BETWEEN e.intime AND e.intime + INTERVAL 48 HOUR
  GROUP BY o.subject_id, o.hadm_id
),
hospital_mortality AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_icu e
    ON a.subject_id = e.subject_id AND a.hadm_id = e.hadm_id
),
combined AS (
  SELECT 
    e.subject_id,
    e.hadm_id,
    e.stay_id,
    e.los,
    cs.composite_score,
    hfnc.stay_id IS NOT NULL AS received_hfnc,
    hm.hospital_expire_flag
  FROM eligible_icu e
  LEFT JOIN composite_score cs
    ON e.subject_id = cs.subject_id AND e.hadm_id = cs.hadm_id
  LEFT JOIN hfnc_admin hfnc
    ON e.subject_id = hfnc.subject_id AND e.hadm_id = hfnc.hadm_id
  LEFT JOIN hospital_mortality hm
    ON e.subject_id = hm.subject_id AND e.hadm_id = hm.hadm_id
  WHERE 
    hfnc.stay_id IS NOT NULL  -- Only patients who received HFNC
    AND cs.composite_score IS NOT NULL  -- Only patients with composite score
),
top_decile AS (
  SELECT 
    *,
    NTILE(10) OVER (ORDER BY composite_score DESC) AS decile
  FROM combined
),
percentile_calc AS (
  SELECT 
    (SELECT COUNT(*) FROM combined WHERE composite_score <= 85) * 100.0 / COUNT(*) AS percentile_85
  FROM combined
)
SELECT 
  (SELECT percentile_85 FROM percentile_calc) AS percentile_85,
  (SELECT AVG(los / 24.0) FROM top_decile WHERE decile = 10) AS avg_los_top_decile,
  (SELECT AVG(hospital_expire_flag) * 100.0 FROM top_decile WHERE decile = 10) AS mortality_top_decile
FROM top_decile
LIMIT 1;