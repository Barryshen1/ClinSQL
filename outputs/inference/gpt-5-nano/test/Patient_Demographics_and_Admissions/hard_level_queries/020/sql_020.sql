WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    -- female
    UPPER(p.gender) = 'F'
    -- age 76-86
    AND p.anchor_age BETWEEN 76 AND 86
    -- Medicare insurance
    AND LOWER(a.insurance) LIKE '%medicare%'
    -- principal AMI on index admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND di.seq_num = 1
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '410%')
          OR
          (di.icd_version = 10 AND di.icd_code LIKE 'I21%')
        )
    )
    -- transferred from another hospital
    AND (
      LOWER(a.admission_type) LIKE '%transfer%'
      OR EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.transfers` AS t
        WHERE t.subject_id = a.subject_id
          AND t.hadm_id = a.hadm_id
          AND LOWER(t.eventtype) LIKE '%transfer%'
      )
    )
),
index_with_readmission AS (
  SELECT
    c.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
      WHERE a2.subject_id = c.subject_id
        AND a2.hadm_id <> c.hadm_id
        AND a2.admittime >= c.dischtime
        AND a2.admittime < TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
    ) AS readmit_within_30
  FROM cohort AS c
)
SELECT
  100.0 * SAFE_DIVIDE(SUM(CASE WHEN readmit_within_30 THEN 1 ELSE 0 END), COUNT(*)) AS readmission_rate_30d,
  MEDIAN(CASE WHEN readmit_within_30 THEN los_days END) AS median_los_readmit_days,
  MEDIAN(CASE WHEN NOT readmit_within_30 THEN los_days END) AS median_los_not_readmit_days,
  100.0 * SAFE_DIVIDE(SUM(CASE WHEN los_days > 4 THEN 1 ELSE 0 END), COUNT(*)) AS percent_index_los_gt4_days
FROM index_with_readmission;