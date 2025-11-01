WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    p.gender,
    p.anchor_age,
    icu.intime,
    icu.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
  JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE (
      (d.icd_version = 9 AND d.icd_code IN ('51881','51882','51884'))
      OR
      (d.icd_version = 10 AND dd.long_title LIKE 'Acute respiratory failure%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'J96%')
    )
  ) dx
    ON icu.hadm_id = dx.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
),
score_calc AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.gender,
    c.anchor_age,
    c.intime,
    c.los,
    c.hospital_expire_flag,
    -- Example score calculation: sum of z-scores of HR and mean BP
    AVG(CASE WHEN di.label IN ('Heart Rate') THEN ce.valuenum END) AS mean_hr,
    AVG(CASE WHEN di.label IN ('Mean BP') THEN ce.valuenum END) AS mean_bp,
    STDDEV(CASE WHEN di.label IN ('Heart Rate') THEN ce.valuenum END) AS sd_hr,
    STDDEV(CASE WHEN di.label IN ('Mean BP') THEN ce.valuenum END) AS sd_bp,
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.label IN ('Heart Rate', 'Mean BP')
    AND ce.valuenum IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id, c.stay_id, c.gender, c.anchor_age, c.intime, c.los, c.hospital_expire_flag
),
instability AS (
  SELECT
    *,
    -- Simple instability score: (sd_hr + sd_bp)*10 as placeholder
    (COALESCE(sd_hr,0) + COALESCE(sd_bp,0)) * 10 AS instability_score
  FROM score_calc
),
percentile_rank AS (
  SELECT
    85 AS target_score,
    ROUND(100 * COUNTIF(instability_score <= 85) / COUNT(*), 1) AS percentile_rank
  FROM instability
),
quartiles AS (
  SELECT
    i.*,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM instability i
)
SELECT
  pr.target_score,
  pr.percentile_rank,
  ROUND(AVG(CASE WHEN q.quartile = 4 THEN q.los END), 2) AS avg_los_top_quartile,
  ROUND(AVG(CASE WHEN q.quartile = 4 THEN q.hospital_expire_flag END) * 100, 1) AS mortality_rate_top_quartile
FROM percentile_rank pr
CROSS JOIN quartiles q
GROUP BY pr.target_score, pr.percentile_rank
ORDER BY pr.target_score;