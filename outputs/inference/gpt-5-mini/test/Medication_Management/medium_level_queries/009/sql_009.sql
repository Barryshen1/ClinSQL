WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    LOWER(p.gender) = 'm'
    AND p.anchor_age BETWEEN 68 AND 78
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime
  HAVING
    SUM(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) > 0
    AND SUM(CASE WHEN LOWER(dd.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) > 0
),

-- For each admission, find earliest prescription starttime for insulin and for oral agents
med_times AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    MIN(CASE WHEN LOWER(pr.drug) LIKE '%insulin%' THEN pr.starttime END) AS insulin_first_start,
    MIN(
      CASE
        WHEN NOT LOWER(pr.drug) LIKE '%insulin%'
         AND REGEXP_CONTAINS(
           LOWER(pr.drug),
           '(metformin|glipizide|glyburide|glimepiride|sitagliptin|saxagliptin|linagliptin|alogliptin|canagliflozin|dapagliflozin|empagliflozin|pioglitazone|rosiglitazone|repaglinide|nateglinide|acarbose|miglitol|voglibose|tolbutamide|chlorpropamide)'
         )
        THEN pr.starttime
      END
    ) AS oral_first_start
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = c.hadm_id
    -- only consider prescriptions with a timestamp
    AND pr.starttime IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime
)

SELECT
  med_class,
  total_admissions,
  n_first24,
  ROUND(100.0 * SAFE_DIVIDE(n_first24, total_admissions), 2) AS pct_first24,
  n_final24,
  ROUND(100.0 * SAFE_DIVIDE(n_final24, total_admissions), 2) AS pct_final24,
  ROUND(ABS(100.0 * SAFE_DIVIDE(n_first24, total_admissions) - 100.0 * SAFE_DIVIDE(n_final24, total_admissions)), 2) AS abs_pct_point_diff
FROM (
  SELECT
    'insulin' AS med_class,
    COUNT(*) AS total_admissions,
    SUM(CASE
          WHEN insulin_first_start IS NOT NULL
           AND insulin_first_start BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 24 HOUR)
          THEN 1 ELSE 0 END) AS n_first24,
    SUM(CASE
          WHEN insulin_first_start IS NOT NULL
           AND insulin_first_start BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR) AND dischtime
          THEN 1 ELSE 0 END) AS n_final24
  FROM med_times

  UNION ALL

  SELECT
    'oral' AS med_class,
    COUNT(*) AS total_admissions,
    SUM(CASE
          WHEN oral_first_start IS NOT NULL
           AND oral_first_start BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 24 HOUR)
          THEN 1 ELSE 0 END) AS n_first24,
    SUM(CASE
          WHEN oral_first_start IS NOT NULL
           AND oral_first_start BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR) AND dischtime
          THEN 1 ELSE 0 END) AS n_final24
  FROM med_times
)
ORDER BY med_class;