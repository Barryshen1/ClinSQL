WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    p.anchor_age,
    adm.admission_type,
    adm.hospital_expire_flag,
    icu.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.subject_id = adm.subject_id
     AND icu.hadm_id    = adm.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
    -- require at least one procedure → “post-op”
    JOIN (
      SELECT DISTINCT subject_id, hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    ) proc
      ON icu.subject_id = proc.subject_id
     AND icu.hadm_id    = proc.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
),

vital_events AS (
  SELECT
    ce.stay_id,
    SUM(CASE WHEN LOWER(di.label) LIKE '%temp%'        AND ce.valuenum > 38.5 THEN 1 ELSE 0 END) AS fever_count,
    SUM(CASE WHEN LOWER(di.label) LIKE '%spo2%'        AND ce.valuenum <  90   THEN 1 ELSE 0 END) AS hypox_count,
    SUM(CASE WHEN LOWER(di.label) LIKE '%respiratory%'  AND ce.valuenum > 20    THEN 1 ELSE 0 END) AS tachypnea_count
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    JOIN cohort c
      ON ce.stay_id = c.stay_id
  WHERE
    ce.valuenum IS NOT NULL
  GROUP BY
    ce.stay_id
),

scores AS (
  SELECT
    c.*,
    COALESCE(ve.fever_count, 0)      AS fever_count,
    COALESCE(ve.hypox_count, 0)      AS hypox_count,
    COALESCE(ve.tachypnea_count, 0)  AS tachypnea_count,
    -- define instability score
    (COALESCE(ve.fever_count, 0)
     + COALESCE(ve.hypox_count, 0)
     + COALESCE(ve.tachypnea_count, 0)
    ) AS instability_score
  FROM
    cohort c
    LEFT JOIN vital_events ve
      ON c.stay_id = ve.stay_id
),

quartiled AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM
    scores
),

top_quartile AS (
  SELECT *
  FROM quartiled
  WHERE quartile = 4
),

-- 95th percentile instability in top quartile
percentile_95 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS instability_95th
  FROM
    top_quartile
),

-- aggregate metrics by group
aggregates AS (
  SELECT
    CASE WHEN quartile = 4 THEN 'Top_Quartile' ELSE 'Other_Quartiles' END AS group_label,
    COUNT(*)                                       AS n_patients,
    AVG(fever_count)           AS avg_fever_episodes,
    AVG(hypox_count)           AS avg_spo2_below90,
    AVG(tachypnea_count)       AS avg_rr_above20,
    AVG(los)                   AS avg_icu_los_days,
    AVG(hospital_expire_flag)  AS in_hosp_mortality_rate
  FROM
    quartiled
  GROUP BY
    group_label
)

SELECT
  p.instability_95th,
  a.*
FROM
  percentile_95 p
CROSS JOIN
  aggregates a
ORDER BY
  a.group_label;