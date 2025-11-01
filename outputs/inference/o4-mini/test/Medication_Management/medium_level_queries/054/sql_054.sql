WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
),
hx AS (
  -- admissions having diagnoses of diabetes or heart failure
  SELECT
    d.subject_id,
    d.hadm_id,
    dd.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      USING (icd_code, icd_version)
  WHERE
    LOWER(dd.long_title) LIKE '%diabetes%'
    OR LOWER(dd.long_title) LIKE '%heart failure%'
),
hf_diabetes_admissions AS (
  SELECT
    subject_id,
    hadm_id
  FROM
    hx
  GROUP BY
    subject_id,
    hadm_id
  HAVING
    COUNT(DISTINCT CASE WHEN LOWER(long_title) LIKE '%diabetes%' THEN 1 END) > 0
    AND COUNT(DISTINCT CASE WHEN LOWER(long_title) LIKE '%heart failure%' THEN 1 END) > 0
),
glp_associations AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    -- first 48h flag
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        WHERE p.hadm_id = c.hadm_id
          AND p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
          AND LOWER(p.drug) IN (
            'exenatide',
            'liraglutide',
            'dulaglutide',
            'semaglutide',
            'albiglutide'
          )
      ) THEN 1 ELSE 0
    END AS first48_use,
    -- final 24h flag
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        WHERE p.hadm_id = c.hadm_id
          AND p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
          AND LOWER(p.drug) IN (
            'exenatide',
            'liraglutide',
            'dulaglutide',
            'semaglutide',
            'albiglutide'
          )
      ) THEN 1 ELSE 0
    END AS final24_use
  FROM
    cohort c
    JOIN hf_diabetes_admissions h
      USING (subject_id, hadm_id)
)
SELECT
  COUNT(*) AS total_admissions,
  SUM(first48_use) AS admissions_with_glp1_first48,
  ROUND(100.0 * SUM(first48_use) / COUNT(*), 2) AS pct_first48,
  SUM(final24_use) AS admissions_with_glp1_final24,
  ROUND(100.0 * SUM(final24_use) / COUNT(*), 2) AS pct_final24,
  ROUND(
    100.0 * SUM(final24_use) / COUNT(*)
    - 100.0 * SUM(first48_use) / COUNT(*),
    2
  ) AS net_change_pct
FROM
  glp_associations;