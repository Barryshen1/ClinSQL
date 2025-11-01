WITH aki_index AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 61 AND 71
    AND a.insurance = 'Medicare'
    AND LOWER(a.admission_location) LIKE '%skilled nursing%'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '584%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
readmit AS (
  SELECT
    idx.subject_id,
    idx.hadm_id,
    MIN(next.admittime) AS next_admittime
  FROM aki_index idx
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next
    ON idx.subject_id = next.subject_id
    AND idx.hadm_id != next.hadm_id
    AND next.admittime > idx.dischtime
    AND next.admittime <= DATETIME_ADD(idx.dischtime, INTERVAL 30 DAY)
  GROUP BY idx.subject_id, idx.hadm_id
),
final AS (
  SELECT
    i.*,
    CASE WHEN r.next_admittime IS NOT NULL THEN 1 ELSE 0 END AS readmit_30d
  FROM aki_index i
  LEFT JOIN readmit r
    ON i.subject_id = r.subject_id
   AND i.hadm_id = r.hadm_id
)
SELECT
  COUNT(*) AS n_index_admissions,
  ROUND(SUM(readmit_30d)/COUNT(*)*100,1) AS readmit_rate_percent,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days_overall,
  APPROX_QUANTILES(IF(readmit_30d=1, los_days, NULL), 100)[OFFSET(50)] AS median_los_days_readmit,
  APPROX_QUANTILES(IF(readmit_30d=0, los_days, NULL), 100)[OFFSET(50)] AS median_los_days_no_readmit,
  ROUND(SUM(CASE WHEN los_days > 6 THEN 1 ELSE 0 END)/COUNT(*)*100,1) AS pct_los_gt6
FROM final;