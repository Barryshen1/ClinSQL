WITH female_68_78 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),

trauma_icd AS (
  -- ICD-9: 800-959, ICD-10: S00-T14 (trauma codes)
  SELECT
    d.subject_id,
    d.hadm_id,
    COUNT(DISTINCT d.icd_code) AS trauma_dx_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    (
      (d.icd_version = 9 AND SAFE_CAST(SUBSTR(d.icd_code, 1, 3) AS INT64) BETWEEN 800 AND 959)
      OR
      (d.icd_version = 10 AND (
        LEFT(d.icd_code, 1) = 'S'
        OR LEFT(d.icd_code, 1) = 'T'
      ))
    )
  GROUP BY
    d.subject_id, d.hadm_id
),

multi_trauma_admissions AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.admittime,
    f.dischtime,
    f.hospital_expire_flag
  FROM
    female_68_78 f
    JOIN trauma_icd t
      ON f.subject_id = t.subject_id AND f.hadm_id = t.hadm_id
  WHERE
    t.trauma_dx_count >= 2
),

first24h_prescriptions AS (
  SELECT
    mta.subject_id,
    mta.hadm_id,
    pr.drug,
    pr.starttime,
    pr.stoptime
  FROM
    multi_trauma_admissions mta
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON mta.subject_id = pr.subject_id AND mta.hadm_id = pr.hadm_id
  WHERE
    pr.starttime >= mta.admittime
    AND pr.starttime < DATETIME_ADD(mta.admittime, INTERVAL 24 HOUR)
),

-- List of serotonergic drugs (lowercase for matching)
serotonergic_drugs AS (
  SELECT 'fluoxetine' AS drug UNION ALL
  SELECT 'sertraline' UNION ALL
  SELECT 'paroxetine' UNION ALL
  SELECT 'citalopram' UNION ALL
  SELECT 'escitalopram' UNION ALL
  SELECT 'venlafaxine' UNION ALL
  SELECT 'duloxetine' UNION ALL
  SELECT 'amitriptyline' UNION ALL
  SELECT 'nortriptyline' UNION ALL
  SELECT 'imipramine' UNION ALL
  SELECT 'clomipramine' UNION ALL
  SELECT 'phenelzine' UNION ALL
  SELECT 'tranylcypromine' UNION ALL
  SELECT 'trazodone' UNION ALL
  SELECT 'mirtazapine' UNION ALL
  SELECT 'buspirone' UNION ALL
  SELECT 'tramadol' UNION ALL
  SELECT 'linezolid' UNION ALL
  SELECT 'fentanyl' UNION ALL
  SELECT 'meperidine' UNION ALL
  SELECT 'methadone' UNION ALL
  SELECT 'lithium'
),

complexity_and_serotonergic AS (
  SELECT
    f24.subject_id,
    f24.hadm_id,
    COUNT(DISTINCT LOWER(f24.drug)) AS med_complexity,
    SUM(CASE WHEN sd.drug IS NOT NULL THEN 1 ELSE 0 END) AS serotonergic_drug_count
  FROM
    first24h_prescriptions f24
    LEFT JOIN serotonergic_drugs sd
      ON LOWER(f24.drug) LIKE CONCAT('%', sd.drug, '%')
  GROUP BY
    f24.subject_id, f24.hadm_id
),

final_cohort AS (
  SELECT
    mta.subject_id,
    mta.hadm_id,
    mta.admittime,
    mta.dischtime,
    mta.hospital_expire_flag,
    cac.med_complexity,
    cac.serotonergic_drug_count,
    CASE WHEN cac.serotonergic_drug_count >= 2 THEN 1 ELSE 0 END AS serotonergic_risk,
    DATETIME_DIFF(mta.dischtime, mta.admittime, HOUR)/24.0 AS los_days
  FROM
    multi_trauma_admissions mta
    JOIN complexity_and_serotonergic cac
      ON mta.subject_id = cac.subject_id AND mta.hadm_id = cac.hadm_id
),

-- Compute quartiles and percentiles for complexity
complexity_stats AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY med_complexity) AS complexity_quartile,
    PERCENT_RANK() OVER (ORDER BY med_complexity) AS complexity_percentile
  FROM
    final_cohort
),

-- Aggregate by serotonergic risk group
group_stats AS (
  SELECT
    serotonergic_risk,
    COUNT(*) AS n_admissions,
    APPROX_QUANTILES(med_complexity, 4)[OFFSET(1)] AS complexity_q1,
    APPROX_QUANTILES(med_complexity, 4)[OFFSET(2)] AS complexity_q2,
    APPROX_QUANTILES(med_complexity, 4)[OFFSET(3)] AS complexity_q3,
    APPROX_QUANTILES(med_complexity, 4)[OFFSET(4)] AS complexity_q4,
    AVG(complexity_percentile) AS avg_complexity_percentile,
    AVG(los_days) AS avg_los_days,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END)/COUNT(*) AS mortality_rate
  FROM
    complexity_stats
  GROUP BY
    serotonergic_risk
),

-- LOS and mortality for top quartile
top_quartile_stats AS (
  SELECT
    serotonergic_risk,
    COUNT(*) AS n_top_quartile,
    AVG(los_days) AS avg_los_days_top_quartile,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END)/COUNT(*) AS mortality_rate_top_quartile
  FROM
    complexity_stats
  WHERE
    complexity_quartile = 4
  GROUP BY
    serotonergic_risk
)

-- Final output: group stats and top quartile stats
SELECT
  gs.serotonergic_risk,
  gs.n_admissions,
  gs.complexity_q1,
  gs.complexity_q2,
  gs.complexity_q3,
  gs.complexity_q4,
  gs.avg_complexity_percentile,
  gs.avg_los_days,
  gs.mortality_rate,
  tqs.n_top_quartile,
  tqs.avg_los_days_top_quartile,
  tqs.mortality_rate_top_quartile
FROM
  group_stats gs
  LEFT JOIN top_quartile_stats tqs
    ON gs.serotonergic_risk = tqs.serotonergic_risk
ORDER BY
  gs.serotonergic_risk DESC;