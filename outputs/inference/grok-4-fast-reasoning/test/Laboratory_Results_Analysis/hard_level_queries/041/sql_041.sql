WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
          OR
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
        )
    )
),
scores AS (
  SELECT
    c.*,
    COUNTIF(l.flag IS NOT NULL AND l.flag != '') AS instability_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.subject_id = c.subject_id
    AND l.hadm_id = c.hadm_id
    AND l.charttime >= c.admittime
    AND l.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.flag IS NOT NULL
    AND l.flag != ''
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag
),
percentile_score AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS thresh
  FROM scores
),
control_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
          OR
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
        )
    )
),
control_scores AS (
  SELECT
    cc.*,
    COUNTIF(l.flag IS NOT NULL AND l.flag != '') AS instability_score
  FROM control_cohort cc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.subject_id = cc.subject_id
    AND l.hadm_id = cc.hadm_id
    AND l.charttime >= cc.admittime
    AND l.charttime < TIMESTAMP_ADD(cc.admittime, INTERVAL 48 HOUR)
    AND l.flag IS NOT NULL
    AND l.flag != ''
  GROUP BY
    cc.subject_id,
    cc.hadm_id,
    cc.admittime
),
high_group AS (
  SELECT s.*
  FROM scores s
  CROSS JOIN percentile_score ps
  WHERE s.instability_score >= ps.thresh
)
SELECT
  ps.thresh AS percentile_95_instability_score,
  AVG(hg.hospital_expire_flag) AS high_group_mortality_rate,
  AVG(TIMESTAMP_DIFF(hg.dischtime, hg.admittime, SECOND) / 86400.0) AS high_group_mean_los_days,
  AVG(hg.instability_score) AS high_group_critical_lab_rate,
  (SELECT AVG(cs.instability_score) FROM control_scores cs) AS control_critical_lab_rate
FROM percentile_score ps
CROSS JOIN high_group hg;