WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE
        d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND dd.icd_code LIKE 'E11%'  -- T2DM
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE
        d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND dd.icd_code LIKE 'I50%'  -- Heart failure
    )
),

insulin_orders AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    p.starttime,
    p.stoptime,
    CASE
      WHEN LOWER(p.drug) LIKE '%glargine%'
        OR LOWER(p.drug) LIKE '%detemir%'
        OR LOWER(p.drug) LIKE '%degludec%' THEN 'basal'
      WHEN LOWER(p.drug) LIKE '%lispro%'
        OR LOWER(p.drug) LIKE '%aspart%'
        OR (LOWER(p.drug) LIKE '%regular%' AND LOWER(p.drug) LIKE '%insulin%') THEN 'bolus'
      WHEN LOWER(p.drug) LIKE '%sliding%' THEN 'sliding-scale'
      ELSE NULL
    END AS insulin_type
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON c.subject_id = p.subject_id
      AND c.hadm_id = p.hadm_id
  WHERE
    LOWER(p.drug) LIKE '%insulin%'
),

classified AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN insulin_type = 'basal'
              AND starttime <= TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR)
             THEN 1 ELSE 0 END) AS any_basal_48h,
    MAX(CASE WHEN insulin_type = 'bolus'
              AND starttime <= TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR)
             THEN 1 ELSE 0 END) AS any_bolus_48h,
    MAX(CASE WHEN insulin_type = 'sliding-scale'
              AND starttime <= TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR)
             THEN 1 ELSE 0 END) AS any_sliding_48h,
    MAX(CASE WHEN insulin_type = 'basal'
              AND stoptime >= TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS any_basal_12h,
    MAX(CASE WHEN insulin_type = 'bolus'
              AND stoptime >= TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS any_bolus_12h,
    MAX(CASE WHEN insulin_type = 'sliding-scale'
              AND stoptime >= TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS any_sliding_12h
  FROM insulin_orders
  GROUP BY subject_id, hadm_id
),

regimens AS (
  SELECT
    *,
    CASE
      WHEN any_basal_48h = 1 AND any_bolus_48h = 1 THEN 'basal–bolus'
      WHEN any_basal_48h = 1 AND any_bolus_48h = 0 AND any_sliding_48h = 0 THEN 'basal'
      WHEN any_bolus_48h = 1 AND any_basal_48h = 0 AND any_sliding_48h = 0 THEN 'bolus'
      WHEN any_sliding_48h = 1 AND any_basal_48h = 0 AND any_bolus_48h = 0 THEN 'sliding-scale'
      ELSE 'none'
    END AS regimen_48h,
    CASE
      WHEN any_basal_12h = 1 AND any_bolus_12h = 1 THEN 'basal–bolus'
      WHEN any_basal_12h = 1 AND any_bolus_12h = 0 AND any_sliding_12h = 0 THEN 'basal'
      WHEN any_bolus_12h = 1 AND any_basal_12h = 0 AND any_sliding_12h = 0 THEN 'bolus'
      WHEN any_sliding_12h = 1 AND any_basal_12h = 0 AND any_bolus_12h = 0 THEN 'sliding-scale'
      ELSE 'none'
    END AS regimen_12h
  FROM classified
),

aggregated AS (
  -- First 48h counts
  SELECT
    regimen_48h AS regimen,
    COUNTIF(regimen_48h <> 'none') AS cnt_48h,
    0 AS cnt_12h
  FROM regimens
  GROUP BY regimen_48h

  UNION ALL

  -- Last 12h counts
  SELECT
    regimen_12h AS regimen,
    0 AS cnt_48h,
    COUNTIF(regimen_12h <> 'none') AS cnt_12h
  FROM regimens
  GROUP BY regimen_12h
),

cohort_size AS (
  SELECT COUNT(*) AS total_admissions
  FROM cohort
)

SELECT
  a.regimen,
  ROUND(100.0 * SUM(a.cnt_48h) / c.total_admissions, 1) AS pct_first_48h,
  ROUND(100.0 * SUM(a.cnt_12h) / c.total_admissions, 1) AS pct_last_12h,
  ROUND(
    (100.0 * SUM(a.cnt_12h) / c.total_admissions)
    -
    (100.0 * SUM(a.cnt_48h) / c.total_admissions),
    1
  ) AS net_change
FROM
  aggregated a
  CROSS JOIN cohort_size c
GROUP BY
  a.regimen,
  c.total_admissions
ORDER BY
  a.regimen;