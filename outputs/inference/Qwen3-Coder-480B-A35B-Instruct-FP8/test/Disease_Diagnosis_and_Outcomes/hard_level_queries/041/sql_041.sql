WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.anchor_age,
    p.gender,
    CASE
      WHEN a.deathtime IS NOT NULL AND DATETIME_DIFF(a.deathtime, a.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS died_within_30_days,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    DATETIME_DIFF(a.deathtime, a.admittime, DAY) AS survival_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.anchor_age BETWEEN 68 AND 78
    AND p.gender = 'M'
    AND d.seq_num = 1
    AND dd.icd_code LIKE 'I61%'
),

icu_transfers AS (
  SELECT DISTINCT
    t.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.transfers` t
  WHERE
    LOWER(t.careunit) LIKE '%icu%'
    AND t.eventtype = 'transfer'
),

aki_ards AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN dd.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS has_aki,
    MAX(CASE WHEN dd.icd_code = 'J80' THEN 1 ELSE 0 END) AS has_ards
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.hadm_id IN (SELECT hadm_id FROM cohort)
  GROUP BY
    d.hadm_id
),

sofa_scores AS (
  SELECT
    ce.hadm_id,
    MAX(
      CASE WHEN di.label LIKE '%GCS%' THEN ce.valuenum ELSE NULL END
    ) AS gcs_min,
    MAX(
      CASE WHEN di.label LIKE '%Creatinine%' THEN ce.valuenum ELSE NULL END
    ) AS creatinine_max,
    MAX(
      CASE WHEN di.label LIKE '%Mean BP%' THEN ce.valuenum ELSE NULL END
    ) AS mbp_min
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    ce.hadm_id IN (SELECT hadm_id FROM cohort)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.hadm_id
),

risk_scores AS (
  SELECT
    s.hadm_id,
    COALESCE(15 - s.gcs_min, 0) +
    COALESCE(
      CASE
        WHEN s.creatinine_max >= 5 THEN 4
        WHEN s.creatinine_max >= 3.5 THEN 3
        WHEN s.creatinine_max >= 2 THEN 2
        WHEN s.creatinine_max >= 1.2 THEN 1
        ELSE 0
      END, 0
    ) +
    COALESCE(
      CASE
        WHEN s.mbp_min < 70 THEN 1
        ELSE 0
      END, 0
    ) AS composite_risk_score
  FROM
    sofa_scores s
)

SELECT
  COUNT(*) AS cohort_size,
  AVG(died_within_30_days) AS mortality_30_day,
  AVG(COALESCE(a.has_aki, 0)) AS aki_rate,
  AVG(COALESCE(a.has_ards, 0)) AS ards_rate,
  APPROX_QUANTILES(r.composite_risk_score, 4)[OFFSET(1)] AS risk_score_p25,
  APPROX_QUANTILES(r.composite_risk_score, 4)[OFFSET(2)] AS risk_score_median,
  APPROX_QUANTILES(r.composite_risk_score, 4)[OFFSET(3)] AS risk_score_p75,
  APPROX_QUANTILES(
    CASE WHEN c.died_within_30_days = 1 THEN c.survival_days ELSE NULL END, 2
  )[OFFSET(1)] AS median_survival_days
FROM
  cohort c
JOIN
  icu_transfers i ON c.hadm_id = i.hadm_id
LEFT JOIN
  aki_ards a ON c.hadm_id = a.hadm_id
LEFT JOIN
  risk_scores r ON c.hadm_id = r.hadm_id;