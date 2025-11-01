WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
          OR
          (d.icd_version = 9 AND d.icd_code IN ('25000', '25002'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
          OR
          (d.icd_version = 9 AND d.icd_code = '4280')
        )
    )
),

glp1_meds AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.charttime
  FROM
    physionet-data.mimiciv_3_1_hosp.emar e
  WHERE
    LOWER(e.medication) LIKE '%liraglutide%'
    OR LOWER(e.medication) LIKE '%exenatide%'
    OR LOWER(e.medication) LIKE '%dulaglutide%'
    OR LOWER(e.medication) LIKE '%semaglutide%'
),

presc_glp1 AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime AS charttime
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions pr
  WHERE
    LOWER(pr.drug) LIKE '%liraglutide%'
    OR LOWER(pr.drug) LIKE '%exenatide%'
    OR LOWER(pr.drug) LIKE '%dulaglutide%'
    OR LOWER(pr.drug) LIKE '%semaglutide%'
),

all_glp1 AS (
  SELECT * FROM glp1_meds
  UNION ALL
  SELECT * FROM presc_glp1
),

cohort_glp1 AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE
      WHEN a.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 12 HOUR) THEN 1
      ELSE 0
    END) AS first_12h_flag,
    MAX(CASE
      WHEN a.charttime BETWEEN DATETIME_ADD(c.dischtime, INTERVAL -12 HOUR) AND c.dischtime THEN 1
      ELSE 0
    END) AS final_12h_flag
  FROM
    cohort c
  LEFT JOIN
    all_glp1 a
    ON c.hadm_id = a.hadm_id
  GROUP BY
    c.subject_id, c.hadm_id
),

agg AS (
  SELECT
    COUNT(*) AS total_admissions,
    SUM(first_12h_flag) AS first_12h_count,
    SUM(final_12h_flag) AS final_12h_count
  FROM
    cohort_glp1
)

SELECT
  ROUND(SAFE_DIVIDE(first_12h_count, total_admissions) * 100, 2) AS percent_first_12h,
  ROUND(SAFE_DIVIDE(final_12h_count, total_admissions) * 100, 2) AS percent_final_12h,
  ROUND(
    (SAFE_DIVIDE(final_12h_count, total_admissions) - SAFE_DIVIDE(first_12h_count, total_admissions)) * 100,
    2
  ) AS net_change_percent
FROM
  agg;