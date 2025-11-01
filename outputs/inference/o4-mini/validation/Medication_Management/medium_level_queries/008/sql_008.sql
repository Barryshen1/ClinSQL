WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
      USING (subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      USING (subject_id, hadm_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    -- T2DM ICD‐10 E11*
    AND d1.icd_code LIKE 'E11%'
    AND d1.icd_version = 10
    -- Heart failure ICD‐10 I50*
    AND d2.icd_code LIKE 'I50%'
    AND d2.icd_version = 10
),
med_windows AS (
  SELECT
    c.hadm_id,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN p.route = 'PO' THEN 'oral_agent'
      ELSE NULL
    END AS drug_class,
    MAX(CASE WHEN p.starttime BETWEEN c.admittime 
                        AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS in_first24,
    MAX(CASE WHEN p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR)
                        AND c.dischtime THEN 1 ELSE 0 END) AS in_last48
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON c.hadm_id = p.hadm_id
  WHERE
    (LOWER(p.drug) LIKE '%insulin%' OR p.route = 'PO')
  GROUP BY
    c.hadm_id,
    drug_class
  HAVING
    drug_class IS NOT NULL
),
summary AS (
  SELECT
    drug_class,
    COUNTIF(in_first24 = 1) AS n_first24,
    COUNTIF(in_last48 = 1) AS n_last48,
    COUNTIF(in_first24 = 1 AND in_last48 = 1) AS n_continued,
    COUNTIF(in_first24 = 0 AND in_last48 = 1) AS n_initiated,
    COUNTIF(in_first24 = 1 AND in_last48 = 0) AS n_discontinued
  FROM
    med_windows
  GROUP BY
    drug_class
),
total AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_adm
  FROM cohort
)
SELECT
  s.drug_class,
  s.n_first24,
  ROUND(s.n_first24 / t.total_adm * 100, 1) AS pct_first24,
  s.n_last48,
  ROUND(s.n_last48 / t.total_adm * 100, 1) AS pct_last48,
  s.n_continued,
  s.n_initiated,
  s.n_discontinued
FROM
  summary s
  CROSS JOIN total t
ORDER BY
  drug_class;