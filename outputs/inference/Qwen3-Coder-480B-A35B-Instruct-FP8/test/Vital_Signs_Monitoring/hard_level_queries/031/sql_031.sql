WITH cohort AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.los AS icu_los,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND i.first_careunit IN ('SICU', 'MICU', 'TSICU', 'CSRU', 'CTICU')
),

vitals AS (
  SELECT
    c.stay_id,
    c.charttime,
    MAX(CASE WHEN di.label LIKE '%Temperature%' AND c.valuenum > 38.5 THEN 1 ELSE 0 END) AS fever,
    MAX(CASE WHEN di.label LIKE '%SpO2%' AND c.valuenum < 90 THEN 1 ELSE 0 END) AS spo2_low,
    MAX(CASE WHEN di.label LIKE '%RR%' AND c.valuenum > 20 THEN 1 ELSE 0 END) AS rr_high
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON c.itemid = di.itemid
  WHERE
    c.valuenum IS NOT NULL
    AND c.stay_id IN (SELECT stay_id FROM cohort)
    AND (
      (di.label LIKE '%Temperature%' AND c.valuenum > 30 AND c.valuenum < 45)
      OR
      (di.label LIKE '%SpO2%' AND c.valuenum > 0 AND c.valuenum <= 100)
      OR
      (di.label LIKE '%RR%' AND c.valuenum > 0 AND c.valuenum < 100)
    )
  GROUP BY
    c.stay_id, c.charttime
),

instability_scores AS (
  SELECT
    stay_id,
    COUNT(*) AS instability_score
  FROM
    vitals
  WHERE
    fever = 1 OR spo2_low = 1 OR rr_high = 1
  GROUP BY
    stay_id
),

instability_with_quartile AS (
  SELECT
    c.*,
    COALESCE(i.instability_score, 0) AS instability_score,
    NTILE(4) OVER (ORDER BY COALESCE(i.instability_score, 0) DESC) AS instability_quartile
  FROM
    cohort c
  LEFT JOIN
    instability_scores i
    ON c.stay_id = i.stay_id
),

top_quartile_stats AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95_instability_score
  FROM
    instability_with_quartile
  WHERE
    instability_quartile = 1
),

clinical_metrics AS (
  SELECT
    CASE WHEN instability_quartile = 1 THEN 'Top Quartile' ELSE 'Other' END AS group_name,
    AVG(CASE WHEN v.fever = 1 THEN 1 ELSE 0 END) AS avg_fever_episodes,
    AVG(CASE WHEN v.spo2_low = 1 THEN 1 ELSE 0 END) AS avg_spo2_low_episodes,
    AVG(CASE WHEN v.rr_high = 1 THEN 1 ELSE 0 END) AS avg_rr_high_episodes,
    AVG(icu_los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    instability_with_quartile i
  LEFT JOIN (
    SELECT
      stay_id,
      fever,
      spo2_low,
      rr_high
    FROM
      vitals
  ) v
  ON i.stay_id = v.stay_id
  GROUP BY
    group_name
)

SELECT
  (SELECT p95_instability_score FROM top_quartile_stats) AS p95_instability_score,
  cm.*
FROM
  clinical_metrics cm
ORDER BY
  cm.group_name;