WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON
    icu.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    icu.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON
    icu.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_dx
  ON
    dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 85 AND 95
    AND (
      (dx.icd_version = 9 AND dx.icd_code = '51881')
      OR
      (dx.icd_version = 10 AND dx.icd_code = 'J9600')
    )
),

vitals_first24 AS (
  SELECT
    ch.stay_id,
    COUNT(*) AS instability_score
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ch
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ch.itemid = di.itemid
  JOIN
    cohort co
  ON
    ch.stay_id = co.stay_id
  WHERE
    ch.charttime >= co.intime
    AND ch.charttime <= DATETIME_ADD(co.intime, INTERVAL 24 HOUR)
    AND ch.valuenum IS NOT NULL
    AND (
      (di.label IN ('Heart Rate') AND (ch.valuenum < 50 OR ch.valuenum > 130)) OR
      (di.label IN ('SBP') AND (ch.valuenum < 90 OR ch.valuenum > 180)) OR
      (di.label IN ('Temperature Celsius') AND (ch.valuenum < 36 OR ch.valuenum > 38.5)) OR
      (di.label IN ('SpO2') AND ch.valuenum < 90) OR
      (di.label IN ('Respiratory Rate') AND (ch.valuenum < 8 OR ch.valuenum > 30))
    )
  GROUP BY
    ch.stay_id
),

scored_cohort AS (
  SELECT
    co.*,
    COALESCE(v.instability_score, 0) AS instability_score
  FROM
    cohort co
  LEFT JOIN
    vitals_first24 v
  ON
    co.stay_id = v.stay_id
),

ranked_scores AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile_rank,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS quartile
  FROM
    scored_cohort
)

SELECT
  (SELECT percentile_rank FROM ranked_scores WHERE instability_score = 85 LIMIT 1) AS percentile_rank_of_85,
  AVG(CASE WHEN quartile = 1 THEN los ELSE NULL END) AS avg_los_top_quartile,
  AVG(CASE WHEN quartile = 1 THEN hospital_expire_flag ELSE NULL END) AS mortality_top_quartile
FROM
  ranked_scores;