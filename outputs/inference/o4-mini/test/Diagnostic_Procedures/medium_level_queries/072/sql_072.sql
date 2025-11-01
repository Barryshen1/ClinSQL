WITH
  -- Define the two time windows
  periods AS (
    SELECT 1 AS period_id, '1-4' AS period_label, 1 AS day_start, 4 AS day_end
    UNION ALL
    SELECT 2 AS period_id, '5-8' AS period_label, 5 AS day_start, 8 AS day_end
  ),

  -- Build the cohort of interest and classify primary vs. secondary pancreatitis
  cohort AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      CASE
        WHEN EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          WHERE d.hadm_id = a.hadm_id
            AND ((d.icd_version = 9 AND d.icd_code LIKE '5770%')
              OR (d.icd_version = 10 AND d.icd_code LIKE 'K85%'))
            AND d.seq_num = 1
        ) THEN 'primary'
        ELSE 'secondary'
      END AS pancreatitis_type
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` a
      JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 52 AND 62
      -- Must have acute pancreatitis in any position
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
          AND ((d.icd_version = 9 AND d.icd_code LIKE '5770%')
            OR (d.icd_version = 10 AND d.icd_code LIKE 'K85%'))
      )
  ),

  -- Count procedures per admission per period (0 if none)
  proc_counts AS (
    SELECT
      c.hadm_id,
      c.pancreatitis_type,
      p.period_label,
      COUNT(pi.seq_num) AS proc_count
    FROM
      cohort c
      JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON a.hadm_id = c.hadm_id
      CROSS JOIN periods p
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
        ON pi.hadm_id = c.hadm_id
        AND DATE_DIFF(DATE(pi.chartdate), DATE(a.admittime), DAY) + 1
            BETWEEN p.day_start AND p.day_end
    GROUP BY
      c.hadm_id,
      c.pancreatitis_type,
      p.period_label
  )

-- Final aggregation: mean, min, max procedures per admission
SELECT
  pancreatitis_type,
  period_label AS period,
  ROUND(AVG(proc_count), 2) AS mean_procedures,
  MIN(proc_count)          AS min_procedures,
  MAX(proc_count)          AS max_procedures
FROM
  proc_counts
GROUP BY
  pancreatitis_type,
  period_label
ORDER BY
  pancreatitis_type,
  period_label;