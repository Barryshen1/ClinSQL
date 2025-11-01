WITH cohort AS (
  -- female 86-96 y.o. admissions with both DM and HF diagnoses
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    -- must have at least one DM code
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
             (d.icd_version = 10 AND LEFT(d.icd_code, 3) BETWEEN 'E08' AND 'E13')
             OR (d.icd_version = 9  AND LEFT(d.icd_code, 3) = '250')
            )
    )
    -- must have at least one HF code
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
             (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'I50')
             OR (d.icd_version = 9  AND LEFT(d.icd_code, 3) = '428')
            )
    )
),
presc_windows AS (
  -- classify prescriptions into Insulin vs Oral Agents and flag early/late windows
  SELECT
    c.hadm_id,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      ELSE 'Oral Agents'
    END AS drug_class,
    MAX(CASE
          WHEN p.starttime BETWEEN c.admittime
                               AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
          THEN 1 ELSE 0
        END) AS early_flag,
    MAX(CASE
          WHEN p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
                               AND c.dischtime
          THEN 1 ELSE 0
        END) AS late_flag
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON p.hadm_id = c.hadm_id
  GROUP BY
    c.hadm_id,
    drug_class
),
totals AS (
  -- total number of admissions in the cohort
  SELECT COUNT(DISTINCT hadm_id) AS n_cohort
  FROM cohort
),
rates AS (
  -- compute early/late rates by class
  SELECT
    pw.drug_class,
    ROUND(100.0 * SUM(pw.early_flag) / t.n_cohort, 1) AS pct_early,
    ROUND(100.0 * SUM(pw.late_flag)  / t.n_cohort, 1) AS pct_late
  FROM presc_windows pw
  CROSS JOIN totals t
  GROUP BY
    pw.drug_class,
    t.n_cohort
),
transitions AS (
  -- compute transition counts and percentages
  SELECT
    pw.drug_class,
    CASE WHEN pw.early_flag = 1 THEN 'Y' ELSE 'N' END AS early,
    CASE WHEN pw.late_flag  = 1 THEN 'Y' ELSE 'N' END AS late,
    COUNT(DISTINCT pw.hadm_id) AS n_trans,
    ROUND(100.0 * COUNT(DISTINCT pw.hadm_id) / t.n_cohort, 1) AS pct_trans
  FROM presc_windows pw
  CROSS JOIN totals t
  GROUP BY
    pw.drug_class,
    early,
    late,
    t.n_cohort
)

-- Final output: two result sets via UNION ALL
SELECT
  'Rates by Class' AS report_type,
  drug_class,
  pct_early AS early_12h_pct,
  pct_late  AS late_72h_pct
FROM rates

UNION ALL

SELECT
  'Transitions' AS report_type,
  CONCAT(drug_class, ': ', early, '→', late) AS drug_class,
  n_trans AS early_12h_pct,
  pct_trans AS late_72h_pct
FROM transitions

ORDER BY
  report_type,
  drug_class;