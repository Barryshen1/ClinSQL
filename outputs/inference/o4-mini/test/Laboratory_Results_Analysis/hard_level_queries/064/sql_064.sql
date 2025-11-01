WITH pancreatitis_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON d.icd_code = dicd.icd_code
     AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND LOWER(dicd.long_title) LIKE '%pancreatitis%'
),

pancreas_lab_stats AS (
  SELECT
    pa.hadm_id,
    STDDEV_POP(le.valuenum) AS instability_score,
    MAX(
      CASE
        WHEN le.valuenum < le.ref_range_lower
          OR le.valuenum > le.ref_range_upper
        THEN 1 ELSE 0
      END
    ) AS critical_flag
  FROM
    pancreatitis_adms pa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON pa.hadm_id = le.hadm_id
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime BETWEEN pa.admittime
                        AND TIMESTAMP_ADD(pa.admittime, INTERVAL 48 HOUR)
  GROUP BY
    pa.hadm_id
),

pancreas_quintiles AS (
  SELECT
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag,
    pa.los_days,
    pls.instability_score,
    pls.critical_flag,
    NTILE(5) OVER (ORDER BY pls.instability_score) AS instability_quintile
  FROM
    pancreatitis_adms pa
    JOIN pancreas_lab_stats pls
      ON pa.hadm_id = pls.hadm_id
),

general_non_pancreas AS (
  -- Female age 65-75 admissions WITHOUT any pancreatitis diagnosis
  SELECT
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code
       AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%pancreatitis%'
    )
),

general_lab_stats AS (
  SELECT
    gn.hadm_id,
    MAX(
      CASE
        WHEN le.valuenum < le.ref_range_lower
          OR le.valuenum > le.ref_range_upper
        THEN 1 ELSE 0
      END
    ) AS critical_flag
  FROM
    general_non_pancreas gn
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON gn.hadm_id = le.hadm_id
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime BETWEEN gn.admittime
                        AND TIMESTAMP_ADD(gn.admittime, INTERVAL 48 HOUR)
  GROUP BY
    gn.hadm_id
),

general_critical_rate AS (
  SELECT
    100.0 * AVG(critical_flag) AS pct_critical_general
  FROM
    general_lab_stats
)

SELECT
  pq.instability_quintile                 AS quintile,
  COUNT(*)                                 AS n_admissions,
  ROUND(AVG(pq.instability_score), 3)      AS mean_instability,
  ROUND(AVG(pq.los_days), 2)               AS mean_los_days,
  ROUND(100.0 * AVG(pq.hospital_expire_flag), 2) AS mortality_pct,
  ROUND(100.0 * AVG(pq.critical_flag), 2)       AS pct_with_critical,
  ROUND(gcr.pct_critical_general, 2)            AS pct_critical_in_age_matched
FROM
  pancreas_quintiles pq
  CROSS JOIN general_critical_rate gcr
GROUP BY
  pq.instability_quintile,
  gcr.pct_critical_general
ORDER BY
  pq.instability_quintile;