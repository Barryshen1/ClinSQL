WITH cohort AS (
  -- Female patients age 78-88 with cardiac arrest diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP(a.admittime) AS adm_ts,
    TIMESTAMP(a.dischtime) AS disc_ts,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
     AND a.hadm_id    = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND (
      (d.icd_version = 9  AND d.icd_code = '4275')
      OR
      (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'I46'))
    )
),
meds AS (
  -- Compute medication complexity components over the first 7 days
  SELECT
    c.hadm_id,
    COUNT(DISTINCT p.drug)   AS num_drugs,
    COUNT(DISTINCT p.route)  AS num_routes,
    SUM(CASE
          WHEN LOWER(p.drug) IN ('warfarin','insulin','digoxin') THEN 1
          ELSE 0
        END)                   AS num_high_risk
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON c.hadm_id = p.hadm_id
  WHERE
    TIMESTAMP(p.starttime) BETWEEN c.adm_ts
                             AND TIMESTAMP_ADD(c.adm_ts, INTERVAL 7 DAY)
  GROUP BY
    c.hadm_id
),
scores AS (
  -- Calculate the complexity score
  SELECT
    m.hadm_id,
    (m.num_drugs + 2 * m.num_high_risk + m.num_routes) AS complexity_score
  FROM
    meds m
),
tertiles AS (
  -- Assign each admission to a tertile based on score
  SELECT
    s.*,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM
    scores s
),
readmit_flag AS (
  -- For each admission, flag a 30-day readmission
  SELECT
    c.subject_id,
    c.hadm_id,
    c.adm_ts,
    c.disc_ts,
    c.hospital_expire_flag,
    t.complexity_score,
    t.tertile,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = c.subject_id
        AND TIMESTAMP(a2.admittime) > c.disc_ts
        AND TIMESTAMP(a2.admittime) <= TIMESTAMP_ADD(c.disc_ts, INTERVAL 30 DAY)
    ) AS readmit_30d,
    TIMESTAMP_DIFF(c.disc_ts, c.adm_ts, DAY) AS los_days
  FROM
    cohort c
    JOIN tertiles t
      ON c.hadm_id = t.hadm_id
)
SELECT
  rf.tertile,
  COUNT(*) AS admissions_count,
  MIN(rf.complexity_score) AS score_min,
  MAX(rf.complexity_score) AS score_max,
  ROUND(AVG(rf.los_days), 2) AS mean_los_days,
  ROUND(100 * AVG(CAST(rf.hospital_expire_flag AS FLOAT64)), 2) AS pct_in_hosp_mortality,
  ROUND(100 * AVG(CAST(rf.readmit_30d AS FLOAT64)), 2) AS pct_readmit_30d
FROM
  readmit_flag rf
GROUP BY
  rf.tertile
ORDER BY
  rf.tertile;