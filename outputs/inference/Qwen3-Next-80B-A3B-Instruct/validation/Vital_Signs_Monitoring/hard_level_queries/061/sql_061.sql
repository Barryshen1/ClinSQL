WITH first_24h_vitals AS (
  SELECT
    p.subject_id,
    i.stay_id,
    COUNT(*) AS vital_instability_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.stay_id = ce.stay_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND ce.charttime >= i.intime
    AND ce.charttime <= DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
    AND di.label IN ('Heart Rate', 'MAP', 'Respiratory Rate', 'SpO2', 'Temperature')
    AND ce.valuenum IS NOT NULL
    AND (
      (di.label = 'Heart Rate' AND (ce.valuenum < di.lownormalvalue OR ce.valuenum > di.highnormalvalue))
      OR (di.label = 'MAP' AND (ce.valuenum < di.lownormalvalue OR ce.valuenum > di.highnormalvalue))
      OR (di.label = 'Respiratory Rate' AND (ce.valuenum < di.lownormalvalue OR ce.valuenum > di.highnormalvalue))
      OR (di.label = 'SpO2' AND (ce.valuenum < di.lownormalvalue OR ce.valuenum > di.highnormalvalue))
      OR (di.label = 'Temperature' AND (ce.valuenum < di.lownormalvalue OR ce.valuenum > di.highnormalvalue))
    )
  GROUP BY
    p.subject_id, i.stay_id
),
score_with_decile AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY vital_instability_score) * 100 AS percentile_score,
    NTILE(10) OVER (ORDER BY vital_instability_score) AS decile
  FROM
    first_24h_vitals
),
mortality_and_los AS (
  SELECT
    AVG(i.los) AS mean_icu_los_days,
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) * 100 AS hospital_mortality_pct_top_decile
  FROM
    score_with_decile s
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON s.stay_id = i.stay_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE
    s.decile = 10
)
SELECT
  (SELECT percentile_score FROM score_with_decile WHERE vital_instability_score = 70 LIMIT 1) AS percentile_for_score_70,
  (SELECT mean_icu_los_days FROM mortality_and_los) AS mean_icu_los_days,
  (SELECT hospital_mortality_pct_top_decile FROM mortality_and_los) AS hospital_mortality_pct_top_decile;