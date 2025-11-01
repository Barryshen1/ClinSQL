WITH index_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS LOS_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
     AND a.hadm_id = d.hadm_id
     AND d.seq_num = 1
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.insurance = 'Medicare'
    AND LOWER(a.admission_location) LIKE '%transfer%hospital%'
    AND (
      (d.icd_version = 9 AND STARTS_WITH(d.icd_code, '410'))
      OR (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'I21'))
    )
),
readmit AS (
  SELECT
    ia.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
        WHERE
          a2.subject_id = ia.subject_id
          AND a2.admittime > ia.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_flag
  FROM index_adm AS ia
)
SELECT
  -- 30-day readmission rate
  ROUND(AVG(readmit_flag), 3) AS readmission_rate,
  -- Median LOS for those readmitted
  (
    SELECT
      APPROX_QUANTILES(LOS_days, 2)[OFFSET(1)]
    FROM readmit
    WHERE readmit_flag = 1
  ) AS median_LOS_readmitted,
  -- Median LOS for those not readmitted
  (
    SELECT
      APPROX_QUANTILES(LOS_days, 2)[OFFSET(1)]
    FROM readmit
    WHERE readmit_flag = 0
  ) AS median_LOS_not_readmitted,
  -- Percent of index stays > 4 days
  ROUND(
    100.0 * SUM(IF(LOS_days > 4, 1, 0)) / COUNT(*),
    2
  ) AS pct_index_stays_gt4_days
FROM
  readmit;