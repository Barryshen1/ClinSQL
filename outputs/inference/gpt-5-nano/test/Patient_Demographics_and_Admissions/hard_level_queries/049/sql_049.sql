WITH index_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP(a.admittime) AS admittime_ts,
    TIMESTAMP(a.dischtime) AS dischtime_ts,
    (TIMESTAMP_DIFF(TIMESTAMP(a.dischtime), TIMESTAMP(a.admittime), SECOND) / 86400.0) AS index_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE a.admission_location = 'SNF'
    AND a.insurance = 'Medicare'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 61 AND 71
    -- Principal AKI diagnosis on the index admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND di.seq_num = 1
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '584%')
          OR
          (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
        )
    )
),
index_with_readmission AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.admittime_ts,
    ic.dischtime_ts,
    ic.index_los_days,
    CASE
      -- A 30-day readmission exists if there is any admission within 30 days after discharge
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
        WHERE a2.subject_id = ic.subject_id
          AND TIMESTAMP(a2.admittime) > ic.dischtime_ts
          AND TIMESTAMP(a2.admittime) <= TIMESTAMP_ADD(ic.dischtime_ts, INTERVAL 30 DAY)
      ) THEN TRUE
      ELSE FALSE
    END AS readmitted_30day
  FROM index_cohort ic
)

SELECT
  -- 30-day readmission rate
  AVG(CASE WHEN readmitted_30day THEN 1.0 ELSE 0.0 END) AS readmission_rate_30day,
  -- Median index LOS for readmitted vs non-readmitted
  MEDIAN(CASE WHEN readmitted_30day THEN index_los_days END) AS median_los_readmitted,
  MEDIAN(CASE WHEN NOT readmitted_30day THEN index_los_days END) AS median_los_nonreadmitted,
  -- Percent of index stays with LOS > 6 days
  100.0 * SUM(CASE WHEN index_los_days > 6 THEN 1 ELSE 0 END) / COUNT(*) AS pct_index_los_gt6
FROM index_with_readmission;