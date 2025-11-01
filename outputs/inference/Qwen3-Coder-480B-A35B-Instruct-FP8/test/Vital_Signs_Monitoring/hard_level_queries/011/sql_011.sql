WITH pneumonia_admissions AS (
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%pneumonia%'
),

cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  JOIN
    pneumonia_admissions pneu
    ON icu.hadm_id = pneu.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 55 AND 65
),

abnormal_scores AS (
  SELECT
    c.stay_id,
    SUM(
      CASE WHEN di.label = 'Heart Rate' AND (ce.valuenum < 60 OR ce.valuenum > 100) THEN 1 ELSE 0 END +
      CASE WHEN di.label = 'MAP' AND (ce.valuenum < 65 OR ce.valuenum > 110) THEN 1 ELSE 0 END +
      CASE WHEN di.label = 'Temperature Celsius' AND (ce.valuenum < 36 OR ce.valuenum > 38) THEN 1 ELSE 0 END +
      CASE WHEN di.label = 'GCS Total' AND ce.valuenum < 15 THEN 1 ELSE 0 END +
      CASE WHEN di.label = 'Urine Out' AND ce.valuenum < 30 THEN 1 ELSE 0 END +
      CASE WHEN di.label = 'Lactate' AND ce.valuenum > 2 THEN 1 ELSE 0 END
    ) AS instability_score
  FROM
    cohort c
  JOIN
    physionet-data.mimiciv_3_1_icu.chartevents ce
    ON c.stay_id = ce.stay_id
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE
    ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND di.label IN (
      'Heart Rate',
      'MAP',
      'Temperature Celsius',
      'GCS Total',
      'Urine Out',
      'Lactate'
    )
  GROUP BY
    c.stay_id
),

scored_cohort AS (
  SELECT
    c.*,
    COALESCE(ab.instability_score, 0) AS instability_score
  FROM
    cohort c
  LEFT JOIN
    abnormal_scores ab
    ON c.stay_id = ab.stay_id
),

percentile_result AS (
  SELECT
    PERCENT_RANK() OVER (ORDER BY instability_score) * 100 AS percentile_rank
  FROM
    scored_cohort
  WHERE
    instability_score = 60
  LIMIT 1
),

decile_stats AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.9) OVER () AS p90_threshold
  FROM
    scored_cohort
  LIMIT 1
),

top_decile AS (
  SELECT
    s.*
  FROM
    scored_cohort s
  CROSS JOIN
    decile_stats d
  WHERE
    s.instability_score >= d.p90_threshold
)

SELECT
  (SELECT percentile_rank FROM percentile_result) AS percentile_of_score_60,
  AVG(t.los) AS mean_los_top_decile,
  AVG(CAST(t.hospital_expire_flag AS FLOAT64)) AS mortality_rate_top_decile
FROM
  top_decile t;