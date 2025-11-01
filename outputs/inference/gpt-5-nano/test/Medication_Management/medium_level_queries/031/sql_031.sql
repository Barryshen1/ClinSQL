WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    LOWER(p.gender) = 'male'
    AND p.anchor_age BETWEEN 53 AND 63
    AND EXISTS (
      -- Diabetes diagnosis on this admission
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      -- Heart failure diagnosis on this admission
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd2
        ON di2.icd_code = dd2.icd_code
       AND di2.icd_version = dd2.icd_version
      WHERE di2.subject_id = a.subject_id
        AND di2.hadm_id = a.hadm_id
        AND LOWER(dd2.long_title) LIKE '%heart failure%'
    )
),
glp1 AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  WHERE
    LOWER(pr.drug) LIKE '%liraglutide%'
    OR LOWER(pr.drug) LIKE '%dulaglutide%'
    OR LOWER(pr.drug) LIKE '%exenatide%'
    OR LOWER(pr.drug) LIKE '%lixisenatide%'
    OR LOWER(pr.drug) LIKE '%semaglutide%'
    OR LOWER(pr.drug) LIKE '%albiglutide%'
)

SELECT
  COUNT(*) AS total_cohort,
  SAFE_DIVIDE(SUM(first24), COUNT(*)) * 100 AS pct_initiated_within_24h,
  SAFE_DIVIDE(SUM(last12), COUNT(*)) * 100 AS pct_initiated_within_final_12h
FROM (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE
          WHEN g.starttime BETWEEN c.admittime
                 AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
          THEN 1 ELSE 0 END) AS first24,
    MAX(CASE
          WHEN g.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
                 AND c.dischtime
          THEN 1 ELSE 0 END) AS last12
  FROM
    cohort AS c
  LEFT JOIN
    glp1 AS g
    ON g.subject_id = c.subject_id
   AND g.hadm_id = c.hadm_id
  GROUP BY
    c.subject_id,
    c.hadm_id
) AS t;