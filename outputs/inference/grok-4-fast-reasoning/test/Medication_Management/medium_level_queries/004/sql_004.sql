WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'E11%') OR
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%') OR
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
        )
    )
),
flags AS (
  SELECT
    c.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.emar` e
      WHERE e.subject_id = c.subject_id
        AND e.hadm_id = c.hadm_id
        AND e.charttime >= c.admittime
        AND e.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
        AND (
          LOWER(e.medication) LIKE '%liraglutide%'
          OR LOWER(e.medication) LIKE '%semaglutide%'
          OR LOWER(e.medication) LIKE '%dulaglutide%'
          OR LOWER(e.medication) LIKE '%exenatide%'
          OR LOWER(e.medication) LIKE '%lixisenatide%'
          OR LOWER(e.medication) LIKE '%albiglutide%'
        )
    ) AS started_within_72h,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.emar` e
      WHERE e.subject_id = c.subject_id
        AND e.hadm_id = c.hadm_id
        AND e.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR)
        AND e.charttime <= c.dischtime
        AND (
          LOWER(e.medication) LIKE '%liraglutide%'
          OR LOWER(e.medication) LIKE '%semaglutide%'
          OR LOWER(e.medication) LIKE '%dulaglutide%'
          OR LOWER(e.medication) LIKE '%exenatide%'
          OR LOWER(e.medication) LIKE '%lixisenatide%'
          OR LOWER(e.medication) LIKE '%albiglutide%'
        )
    ) AS on_in_last_48h
  FROM cohort c
)
SELECT
  ROUND(SUM(CASE WHEN started_within_72h THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_started_within_72h,
  ROUND(SUM(CASE WHEN on_in_last_48h THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_on_in_last_48h,
  ROUND(
    (SUM(CASE WHEN started_within_72h THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) -
    (SUM(CASE WHEN on_in_last_48h THEN 1 ELSE 0 END) * 100.0 / COUNT(*)),
    2
  ) AS net_change,
  COUNT(*) AS total_cohort_size
FROM flags;