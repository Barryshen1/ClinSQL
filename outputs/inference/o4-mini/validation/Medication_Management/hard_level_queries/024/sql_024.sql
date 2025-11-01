WITH trauma_adm AS (
  -- Female, age 68-78, multi-trauma admissions
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code
   AND d.icd_version = icd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND LOWER(icd.long_title) LIKE '%trauma%'
),
first24_rx AS (
  -- Prescriptions within first 24h, aggregate complexity and serotonergic flag
  SELECT
    t.subject_id,
    t.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity,
    MAX(
      CASE
        WHEN LOWER(pr.drug) IN (
          'sertraline','fluoxetine','paroxetine','citalopram',
          'escitalopram','venlafaxine','duloxetine',
          'tramadol','linezolid','methylene blue'
        ) THEN 1 ELSE 0
      END
    ) AS serotonergic_flag
  FROM
    trauma_adm t
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON t.hadm_id = pr.hadm_id
   AND pr.starttime BETWEEN t.admittime
                        AND TIMESTAMP_ADD(t.admittime, INTERVAL 24 HOUR)
  GROUP BY
    t.subject_id,
    t.hadm_id
),
with_metrics AS (
  -- Combine with LOS, mortality, percentiles, quartiles
  SELECT
    f.subject_id,
    f.hadm_id,
    f.complexity,
    f.serotonergic_flag,
    -- LOS in days, including fractional part
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    a.hospital_expire_flag,
    PERCENT_RANK() OVER (ORDER BY f.complexity) AS complexity_pct,
    NTILE(4) OVER (ORDER BY f.complexity) AS complexity_quartile
  FROM
    first24_rx f
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.hadm_id = a.hadm_id
),
agg_by_risk AS (
  -- Metrics by serotonergic risk vs other
  SELECT
    CASE WHEN serotonergic_flag = 1 THEN 'Serotonergic-Risk' ELSE 'Other' END AS group_name,
    SUM(CASE WHEN complexity_quartile = 1 THEN 1 ELSE 0 END) AS q1_count,
    SUM(CASE WHEN complexity_quartile = 2 THEN 1 ELSE 0 END) AS q2_count,
    SUM(CASE WHEN complexity_quartile = 3 THEN 1 ELSE 0 END) AS q3_count,
    SUM(CASE WHEN complexity_quartile = 4 THEN 1 ELSE 0 END) AS q4_count,
    AVG(complexity_pct) AS avg_complexity_pct,
    AVG(los_days) AS avg_los_days,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    with_metrics
  GROUP BY
    serotonergic_flag
),
top_quartile AS (
  -- Metrics for top quartile overall, padded to match columns
  SELECT
    'Top-Quartile' AS group_name,
    NULL AS q1_count,
    NULL AS q2_count,
    NULL AS q3_count,
    NULL AS q4_count,
    NULL AS avg_complexity_pct,
    AVG(los_days) AS avg_los_days,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    with_metrics
  WHERE
    complexity_quartile = 4
)

-- Final output: metrics by risk group, then top quartile
SELECT * FROM agg_by_risk
UNION ALL
SELECT * FROM top_quartile;