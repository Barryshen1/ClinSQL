WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.dischtime IS NOT NULL
    AND a.admission_type != 'OUTPATIENT'
),

diabetes_hf_admissions AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime
  FROM
    cohort c
  WHERE
    EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = c.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR (d.icd_version = 10 AND d.icd_code BETWEEN 'E08' AND 'E13')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = c.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),

glp1_ra_prescriptions AS (
  SELECT
    p.hadm_id,
    p.starttime,
    p.stoptime
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions p
  WHERE
    LOWER(p.drug) IN (
      'semaglutide', 'dulaglutide', 'exenatide', 'liraglutide'
    )
    OR LOWER(p.drug) LIKE '%glp-1%'
    OR LOWER(p.drug) LIKE '%glucagon-like peptide%'
),

timed_flags AS (
  SELECT
    d.hadm_id,
    MAX(CASE
      WHEN g.starttime <= d.admittime + INTERVAL 24 HOUR THEN 1
      ELSE 0
    END) AS glp1_first_24h,
    MAX(CASE
      WHEN g.starttime >= d.dischtime - INTERVAL 12 HOUR THEN 1
      ELSE 0
    END) AS glp1_last_12h
  FROM
    diabetes_hf_admissions d
  LEFT JOIN
    glp1_ra_prescriptions g
    ON d.hadm_id = g.hadm_id
  GROUP BY
    d.hadm_id
)

SELECT
  COUNT(*) AS total_admissions,
  SUM(glp1_first_24h) AS count_first_24h,
  SUM(glp1_last_12h) AS count_last_12h,
  ROUND(SUM(glp1_first_24h) * 100.0 / COUNT(*), 2) AS pct_first_24h,
  ROUND(SUM(glp1_last_12h) * 100.0 / COUNT(*), 2) AS pct_last_12h
FROM
  timed_flags;