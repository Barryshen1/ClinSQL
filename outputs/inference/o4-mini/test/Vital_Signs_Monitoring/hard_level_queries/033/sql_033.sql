WITH female_51_61_icustays AS (
  SELECT
    p.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON p.subject_id = icu.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),
instability_scores AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    MAX(ce.valuenum) AS max_instability_score
  FROM
    female_51_61_icustays f
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON f.subject_id = ce.subject_id
     AND f.hadm_id     = ce.hadm_id
     AND f.stay_id     = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%instability score%'
    AND ce.charttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    f.subject_id,
    f.hadm_id,
    f.stay_id
),
score_distribution AS (
  SELECT
    stay_id,
    max_instability_score,
    PERCENT_RANK() OVER (ORDER BY max_instability_score) AS pct_rank
  FROM
    instability_scores
),
percentile_of_80 AS (
  SELECT
    ROUND(pct_rank, 3) AS percentile_rank_of_80
  FROM
    score_distribution
  WHERE
    max_instability_score = 80
  LIMIT 1
),
most_unstable_decile AS (
  SELECT
    sd.stay_id,
    sd.max_instability_score,
    sd.pct_rank,
    f.los,
    ad.hospital_expire_flag AS icu_mortality
  FROM
    score_distribution sd
    JOIN female_51_61_icustays f
      ON sd.stay_id = f.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
      ON f.hadm_id = ad.hadm_id
  WHERE
    sd.pct_rank >= 0.9
)
SELECT
  p80.percentile_rank_of_80,
  ARRAY_AGG(STRUCT(
    m.stay_id,
    m.max_instability_score,
    m.pct_rank,
    m.los AS icu_los,
    m.icu_mortality
  )) AS most_unstable_decile_stats
FROM
  percentile_of_80 p80
  CROSS JOIN most_unstable_decile m
GROUP BY
  p80.percentile_rank_of_80;