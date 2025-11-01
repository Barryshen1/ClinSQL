WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS index_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE di.seq_num = 1
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admission_location = 'SNF'
    AND LOWER(a.insurance) = 'medicare'
    AND LOWER(dd.long_title) LIKE '%acute respiratory failure%'
),
readmit_flag AS (
  SELECT
    ia.subject_id,
    ia.hadm_id,
    ia.admittime,
    ia.dischtime,
    ia.index_los_days,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
      WHERE a2.subject_id = ia.subject_id
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) AS readmit_30d
  FROM index_admissions AS ia
),
ranked AS (
  SELECT
    CASE WHEN readmit_30d THEN 1 ELSE 0 END AS readmission_within_30d,
    index_los_days,
    readmit_30d
  FROM readmit_flag
),
-- Determine median index LOS per group using exact middle value(s)
median_rows AS (
  SELECT
    readmission_within_30d,
    index_los_days
  FROM (
    SELECT
      readmission_within_30d,
      index_los_days,
      ROW_NUMBER() OVER (PARTITION BY readmission_within_30d ORDER BY index_los_days) AS rn,
      COUNT(*) OVER (PARTITION BY readmission_within_30d) AS total_in_group
    FROM ranked
  )
  WHERE
    (MOD(total_in_group, 2) = 1 AND rn = CAST((total_in_group + 1) / 2 AS INT64))
    OR
    (MOD(total_in_group, 2) = 0 AND rn IN (CAST(total_in_group / 2 AS INT64), CAST(total_in_group / 2 + 1 AS INT64)))
),
median_per_group AS (
  SELECT readmission_within_30d, AVG(index_los_days) AS median_index_los_days
  FROM median_rows
  GROUP BY readmission_within_30d
),
count_per_group AS (
  SELECT readmission_within_30d, COUNT(*) AS n_index_admissions_in_group
  FROM ranked
  GROUP BY readmission_within_30d
),
pct_gt8 AS (
  SELECT readmission_within_30d,
         SAFE_DIVIDE(SUM(CASE WHEN index_los_days > 8 THEN 1 ELSE 0 END), COUNT(*)) AS pct_index_los_gt_8
  FROM ranked
  GROUP BY readmission_within_30d
),
overall_rate AS (
  SELECT SAFE_DIVIDE(SUM(CASE WHEN readmit_30d THEN 1 ELSE 0 END), COUNT(*)) AS readmission_rate_30d
  FROM readmit_flag
)
SELECT
  c.readmission_within_30d,
  c.n_index_admissions_in_group,
  m.median_index_los_days,
  p.pct_index_los_gt_8,
  o.readmission_rate_30d
FROM count_per_group AS c
JOIN median_per_group AS m ON m.readmission_within_30d = c.readmission_within_30d
JOIN pct_gt8 AS p ON p.readmission_within_30d = c.readmission_within_30d
CROSS JOIN overall_rate AS o
ORDER BY c.readmission_within_30d;