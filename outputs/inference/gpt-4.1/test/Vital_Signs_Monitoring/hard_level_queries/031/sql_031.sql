WITH itemids AS (
  SELECT
    MAX(CASE WHEN LOWER(label) LIKE '%temperature%' THEN itemid END) AS temp_itemid,
    MAX(CASE WHEN LOWER(label) LIKE '%spo2%' OR LOWER(label) LIKE '%o2 saturation%' THEN itemid END) AS spo2_itemid,
    MAX(CASE WHEN LOWER(label) LIKE '%respiratory rate%' THEN itemid END) AS rr_itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(category) IN ('vital signs', 'vitals')
),

-- Step 2: Get male post-op ICU stays aged 63-73
postop_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    pat.gender,
    adm.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
  -- Post-op: at least one procedure before/during ICU stay
  WHERE EXISTS (
    SELECT 1
    FROM physionet-data.mimiciv_3_1_hosp.procedures_icd proc
    WHERE proc.hadm_id = icu.hadm_id
      AND proc.chartdate <= icu.intime
  )
  AND pat.gender = 'M'
  AND pat.anchor_age BETWEEN 63 AND 73
),

-- Step 3: Calculate instability episodes per ICU stay
instability AS (
  SELECT
    p.stay_id,
    p.subject_id,
    p.hadm_id,
    p.intime,
    p.outtime,
    p.los,
    p.anchor_age,
    p.gender,
    p.hospital_expire_flag,
    -- Fever episodes
    COUNTIF(
      ce.itemid = i.temp_itemid AND ce.valuenum > 38.5
      AND ce.charttime BETWEEN p.intime AND p.outtime
    ) AS fever_episodes,
    -- SpO2<90 episodes
    COUNTIF(
      ce.itemid = i.spo2_itemid AND ce.valuenum < 90
      AND ce.charttime BETWEEN p.intime AND p.outtime
    ) AS spo2_low_episodes,
    -- RR>20 episodes
    COUNTIF(
      ce.itemid = i.rr_itemid AND ce.valuenum > 20
      AND ce.charttime BETWEEN p.intime AND p.outtime
    ) AS rr_high_episodes,
    -- Instability score: sum of all episodes
    (
      COUNTIF(ce.itemid = i.temp_itemid AND ce.valuenum > 38.5 AND ce.charttime BETWEEN p.intime AND p.outtime)
      + COUNTIF(ce.itemid = i.spo2_itemid AND ce.valuenum < 90 AND ce.charttime BETWEEN p.intime AND p.outtime)
      + COUNTIF(ce.itemid = i.rr_itemid AND ce.valuenum > 20 AND ce.charttime BETWEEN p.intime AND p.outtime)
    ) AS instability_score
  FROM postop_icu p
  CROSS JOIN itemids i
  LEFT JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON ce.stay_id = p.stay_id
    AND ce.charttime BETWEEN p.intime AND p.outtime
    AND ce.valuenum IS NOT NULL
    AND ce.itemid IN (i.temp_itemid, i.spo2_itemid, i.rr_itemid)
  GROUP BY
    p.stay_id, p.subject_id, p.hadm_id, p.intime, p.outtime, p.los, p.anchor_age, p.gender, p.hospital_expire_flag
),

-- Step 4: Calculate top quartile cutoff
quartiles AS (
  SELECT
    APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS top_quartile_cutoff
  FROM instability
),

-- Step 5: Mark top quartile and calculate 95th percentile
instability_flagged AS (
  SELECT
    i.*,
    CASE WHEN i.instability_score >= q.top_quartile_cutoff THEN 1 ELSE 0 END AS top_quartile
  FROM instability i
  CROSS JOIN quartiles q
),

percentile_95 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 20)[OFFSET(19)] AS percentile_95
  FROM instability_flagged
  WHERE top_quartile = 1
)

-- Step 6: Compare outcomes
SELECT
  'Top Quartile' AS group_label,
  COUNT(*) AS n_stays,
  ROUND(AVG(fever_episodes),2) AS avg_fever_episodes,
  ROUND(AVG(spo2_low_episodes),2) AS avg_spo2_low_episodes,
  ROUND(AVG(rr_high_episodes),2) AS avg_rr_high_episodes,
  ROUND(AVG(los),2) AS avg_icu_los,
  ROUND(AVG(hospital_expire_flag),3) AS in_hospital_mortality_rate,
  (SELECT percentile_95 FROM percentile_95) AS instability_score_95th_percentile
FROM instability_flagged
WHERE top_quartile = 1

UNION ALL

SELECT
  'Other Post-op' AS group_label,
  COUNT(*) AS n_stays,
  ROUND(AVG(fever_episodes),2) AS avg_fever_episodes,
  ROUND(AVG(spo2_low_episodes),2) AS avg_spo2_low_episodes,
  ROUND(AVG(rr_high_episodes),2) AS avg_rr_high_episodes,
  ROUND(AVG(los),2) AS avg_icu_los,
  ROUND(AVG(hospital_expire_flag),3) AS in_hospital_mortality_rate,
  NULL AS instability_score_95th_percentile
FROM instability_flagged
WHERE top_quartile = 0;