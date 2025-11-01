WITH cohort AS (
  -- Filter male ICU patients aged 74-84 with los >=48h
  SELECT 
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age,
    p.dod
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND i.los >= 48
),

vitals AS (
  -- Join chartevents for relevant itemids (temps, SpO2, RR), restricted to first 48h
  SELECT 
    c.subject_id,
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum,
    c.valueuom,
    i.abbreviation,
    i.category,
    co.intime
  FROM cohort co
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON co.stay_id = c.stay_id
    AND co.subject_id = c.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` i
    ON c.itemid = i.itemid
  WHERE c.charttime >= co.intime
    AND c.charttime < TIMESTAMP_ADD(co.intime, INTERVAL 48 HOUR)
    AND c.valuenum IS NOT NULL
    AND (
      -- Fever: body temp >38.5 C
      (i.category LIKE '%Temperature%' 
       AND (i.itemid IN (676, 677) OR i.label LIKE '%Temp%' OR i.abbreviation IN ('C', '°C'))
       AND c.valuenum > 38.5
       AND c.valueuom IN ('C', '°C'))
      OR
      -- Hypoxemia: SpO2 <90%
      (i.category LIKE '%SpO2%' 
       AND (i.itemid IN (220277, 220339) OR i.label LIKE '%SpO2%' OR i.abbreviation LIKE '%SpO2%')
       AND c.valuenum < 90
       AND c.valueuom IN ('%', '%SpO2'))
      OR
      -- Tachypnea: RR >20
      (i.category LIKE '%Respiratory Rate%' 
       AND (i.itemid = 618 OR i.label LIKE '%Resp Rate%' OR i.abbreviation = 'RR')
       AND c.valuenum > 20
       AND c.valueuom = 'breaths/min')
    )
),

hourly_instability AS (
  -- Count distinct unstable hours per stay (any of the 3 conditions) in first 48h
  SELECT 
    v.stay_id,
    FLOOR(TIMESTAMP_DIFF(v.charttime, v.intime, HOUR)) AS relative_hour,
    -- Flag if any instability in this hour
    LOGICAL_OR(
      CASE 
        WHEN v.category LIKE '%Temperature%' AND v.valuenum > 38.5 THEN TRUE
        WHEN v.category LIKE '%SpO2%' AND v.valuenum < 90 THEN TRUE
        WHEN v.category LIKE '%Respiratory Rate%' AND v.valuenum > 20 THEN TRUE
        ELSE FALSE 
      END
    ) AS is_unstable_hour
  FROM vitals v
  GROUP BY v.stay_id, relative_hour
),

stay_instability AS (
  -- Aggregate to per-stay instability hours
  SELECT 
    co.stay_id,
    co.los,
    co.intime,
    co.outtime,
    co.dod,
    -- Total distinct unstable hours in first 48h (max 48)
    COUNT(DISTINCT CASE WHEN hi.is_unstable_hour THEN hi.relative_hour END) AS instability_hours
  FROM cohort co
  LEFT JOIN hourly_instability hi
    ON co.stay_id = hi.stay_id
  GROUP BY co.stay_id, co.los, co.intime, co.outtime, co.dod
),

p90 AS (
  -- Compute 90th percentile instability as scalar
  SELECT PERCENTILE_CONT(0.9, input => instability_hours) AS p90_instability
  FROM stay_instability
),

top_decile_stats AS (
  -- Filter top decile stays and compute aggregates
  SELECT 
    COUNT(*) AS n,
    AVG(si.los) AS mean_icu_los,
    -- Mortality: approximate ICU mortality if death during stay (dod between in/out)
    AVG(CASE 
      WHEN si.dod IS NOT NULL 
        AND si.intime <= si.dod 
        AND si.dod <= si.outtime 
      THEN 1.0 
      ELSE 0.0 
    END) * 100 AS mortality_pct
  FROM stay_instability si
  CROSS JOIN p90 p
  WHERE si.instability_hours >= p.p90_instability
)

-- Main results: 90th percentile + top decile summary
SELECT 
  p.p90_instability AS percentile_90_instability_hours,
  tds.n,
  tds.mean_icu_los,
  tds.mortality_pct
FROM p90 p
CROSS JOIN top_decile_stats tds;