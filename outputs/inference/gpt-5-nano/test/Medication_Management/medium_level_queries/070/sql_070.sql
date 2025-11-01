WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE (p.gender = 'F' OR LOWER(p.gender) = 'female')
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
first48_by_hadm AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%metformin%' 
             AND pr.starttime >= c.admittime
             AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
             THEN 1 ELSE 0 END) AS metformin_48_present,
    MAX(CASE WHEN (
                  LOWER(pr.drug) LIKE '%glipizide%' OR
                  LOWER(pr.drug) LIKE '%glyburide%' OR
                  LOWER(pr.drug) LIKE '%glimepiride%' OR
                  LOWER(pr.drug) LIKE '%gliclazide%' OR
                  LOWER(pr.drug) LIKE '%chlorpropamide%' OR
                  LOWER(pr.drug) LIKE '%tolbutamide%' OR
                  LOWER(pr.drug) LIKE '%tolazamide%'
                )
             AND pr.starttime >= c.admittime
             AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
             THEN 1 ELSE 0 END) AS sulfonyl_48_present,
    MAX(CASE WHEN (
                  LOWER(pr.drug) LIKE '%sitagliptin%' OR
                  LOWER(pr.drug) LIKE '%saxagliptin%' OR
                  LOWER(pr.drug) LIKE '%linagliptin%' OR
                  LOWER(pr.drug) LIKE '%alogliptin%' OR
                  LOWER(pr.drug) LIKE '%vildagliptin%'
                )
             AND pr.starttime >= c.admittime
             AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
             THEN 1 ELSE 0 END) AS dpp4_48_present,
    MAX(CASE WHEN (
                  LOWER(pr.drug) LIKE '%empagliflozin%' OR
                  LOWER(pr.drug) LIKE '%canagliflozin%' OR
                  LOWER(pr.drug) LIKE '%dapagliflozin%' OR
                  LOWER(pr.drug) LIKE '%ertugliflozin%'
                )
             AND pr.starttime >= c.admittime
             AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
             THEN 1 ELSE 0 END) AS sglt2_48_present
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = c.hadm_id
   AND pr.subject_id = c.subject_id
  GROUP BY c.hadm_id
),
first48_pct AS (
  SELECT
    AVG(metformin_48_present) AS metformin_48_pct,
    AVG(sulfonyl_48_present) AS sulfonyl_48_pct,
    AVG(dpp4_48_present) AS dpp4_48_pct,
    AVG(sglt2_48_present) AS sglt2_48_pct
  FROM first48_by_hadm
),
last12_by_hadm AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%metformin%' 
             AND pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
             AND pr.starttime <= c.dischtime
             THEN 1 ELSE 0 END) AS metformin_last12_present,
    MAX(CASE WHEN (
                  LOWER(pr.drug) LIKE '%glipizide%' OR
                  LOWER(pr.drug) LIKE '%glyburide%' OR
                  LOWER(pr.drug) LIKE '%glimepiride%' OR
                  LOWER(pr.drug) LIKE '%gliclazide%' OR
                  LOWER(pr.drug) LIKE '%chlorpropamide%' OR
                  LOWER(pr.drug) LIKE '%tolbutamide%' OR
                  LOWER(pr.drug) LIKE '%tolazamide%'
                )
             AND pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
             AND pr.starttime <= c.dischtime
             THEN 1 ELSE 0 END) AS sulfonyl_last12_present,
    MAX(CASE WHEN (
                  LOWER(pr.drug) LIKE '%sitagliptin%' OR
                  LOWER(pr.drug) LIKE '%saxagliptin%' OR
                  LOWER(pr.drug) LIKE '%linagliptin%' OR
                  LOWER(pr.drug) LIKE '%alogliptin%' OR
                  LOWER(pr.drug) LIKE '%vildagliptin%'
                )
             AND pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
             AND pr.starttime <= c.dischtime
             THEN 1 ELSE 0 END) AS dpp4_last12_present,
    MAX(CASE WHEN (
                  LOWER(pr.drug) LIKE '%empagliflozin%' OR
                  LOWER(pr.drug) LIKE '%canagliflozin%' OR
                  LOWER(pr.drug) LIKE '%dapagliflozin%' OR
                  LOWER(pr.drug) LIKE '%ertugliflozin%'
                )
             AND pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
             AND pr.starttime <= c.dischtime
             THEN 1 ELSE 0 END) AS sglt2_last12_present
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = c.hadm_id
   AND pr.subject_id = c.subject_id
  GROUP BY c.hadm_id
),
last12_pct AS (
  SELECT
    AVG(metformin_last12_present) AS metformin_last12_pct,
    AVG(sulfonyl_last12_present) AS sulfonyl_last12_pct,
    AVG(dpp4_last12_present) AS dpp4_last12_pct,
    AVG(sglt2_last12_present) AS sglt2_last12_pct
  FROM last12_by_hadm
)
SELECT
  f.metformin_48_pct,
  l.metformin_last12_pct,
  (l.metformin_last12_pct - f.metformin_48_pct) AS metformin_change,
  f.sulfonyl_48_pct,
  l.sulfonyl_last12_pct,
  (l.sulfonyl_last12_pct - f.sulfonyl_48_pct) AS sulfonyl_change,
  f.dpp4_48_pct,
  l.dpp4_last12_pct,
  (l.dpp4_last12_pct - f.dpp4_48_pct) AS dpp4_change,
  f.sglt2_48_pct,
  l.sglt2_last12_pct,
  (l.sglt2_last12_pct - f.sglt2_48_pct) AS sglt2_change
FROM first48_pct AS f
CROSS JOIN last12_pct AS l;