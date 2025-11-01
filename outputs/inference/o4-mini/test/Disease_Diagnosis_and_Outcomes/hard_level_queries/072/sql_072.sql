WITH
-- 1. Base female cohort in age window with at least one ICU stay
base_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    ic.stay_id,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
      ON a.subject_id = ic.subject_id
     AND a.hadm_id   = ic.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
),

-- 2. Identify ACS admissions
acs_cohort AS (
  SELECT DISTINCT
    bc.*,
    1 AS is_acs
  FROM
    base_cohort bc
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON bc.subject_id = d.subject_id
     AND bc.hadm_id     = d.hadm_id
  WHERE
    (
      (d.icd_version = 9  AND d.icd_code LIKE '410%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I2%')
    )
),

-- 3. Age-matched general ICU cohort (no ACS)
general_cohort AS (
  SELECT
    bc.*,
    0 AS is_acs
  FROM
    base_cohort bc
  LEFT JOIN acs_cohort ac
    ON bc.subject_id = ac.subject_id
   AND bc.hadm_id     = ac.hadm_id
  WHERE
    ac.hadm_id IS NULL
),

-- 4. Combine cohorts
combined AS (
  SELECT * FROM acs_cohort
  UNION ALL
  SELECT * FROM general_cohort
),

-- 5. Append risk score
with_scores AS (
  SELECT
    c.*,
    rs.score AS risk_score
  FROM
    combined c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.risk_scores` rs
      ON c.subject_id = rs.subject_id
     AND c.hadm_id     = rs.hadm_id
),

-- 6. Compute outcomes and complications
outcomes AS (
  SELECT
    ws.*,
    CASE
      WHEN ws.deathtime IS NOT NULL
       AND DATE_DIFF(DATE(ws.deathtime), DATE(ws.admittime), DAY) <= 30
      THEN 1 ELSE 0
    END AS died_within_30d,
    EXISTS(
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.subject_id = ws.subject_id
        AND d2.hadm_id     = ws.hadm_id
        AND (
             (d2.icd_version = 9  AND d2.icd_code IN ('4280','4281','78551'))
          OR (d2.icd_version = 10 AND d2.icd_code IN ('I50.0','I50.1','R57.0'))
        )
        AND d2.seq_num > 1
    ) AS cardiac_complication,
    EXISTS(
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d3
      WHERE d3.subject_id = ws.subject_id
        AND d3.hadm_id     = ws.hadm_id
        AND (
             (d3.icd_version = 9  AND (
                  d3.icd_code LIKE '430%' OR d3.icd_code LIKE '431%' OR
                  d3.icd_code LIKE '432%' OR d3.icd_code LIKE '433%' OR
                  d3.icd_code LIKE '434%' OR d3.icd_code LIKE '435%' OR
                  d3.icd_code LIKE '436%' OR d3.icd_code LIKE '437%' OR
                  d3.icd_code LIKE '438%' OR d3.icd_code = '78039'
             ))
          OR (d3.icd_version = 10 AND (
                  d3.icd_code LIKE 'I6%' OR d3.icd_code = 'R56.9'
             ))
        )
        AND d3.seq_num > 1
    ) AS neuro_complication,
    ic.los
  FROM
    with_scores ws
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
      ON ws.subject_id = ic.subject_id
     AND ws.hadm_id     = ic.hadm_id
     AND ws.stay_id     = ic.stay_id
),

-- 7. Compute percentile ranks of risk score in combined sample
ranked AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY risk_score) AS risk_score_pctile
  FROM
    outcomes
)

-- 8. Final aggregation
SELECT
  is_acs,
  COUNT(1)                                                AS n_patients,
  ROUND(AVG(risk_score), 2)                              AS mean_risk_score,
  ROUND(AVG(died_within_30d), 3)                         AS mortality_30d_rate,
  ROUND(AVG(CAST(cardiac_complication AS INT64)), 3)     AS cardiac_comp_rate,
  ROUND(AVG(CAST(neuro_complication AS INT64)), 3)       AS neuro_comp_rate,
  ROUND(
    AVG(CASE WHEN died_within_30d = 0 THEN los END)
    , 2
  )                                                       AS mean_icu_los_survivors,
  ROUND(AVG(risk_score_pctile) * 100, 1)                  AS mean_matched_profile_pctile
FROM
  ranked
GROUP BY
  is_acs
ORDER BY
  is_acs DESC;