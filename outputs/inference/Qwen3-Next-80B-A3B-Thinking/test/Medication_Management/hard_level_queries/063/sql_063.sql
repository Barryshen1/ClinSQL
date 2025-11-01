WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    pr.drug,
    pr.starttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON a.hadm_id = pr.hadm_id
    AND pr.starttime >= a.admittime
    AND pr.starttime <= a.admittime + INTERVAL '24 hour'
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
),
medication_data AS (
  SELECT
    subject_id,
    COUNT(DISTINCT drug) AS num_meds,
    MAX(CASE WHEN drug IN ('sertraline', 'fluoxetine', 'paroxetine', 'venlafaxine', 'duloxetine', 'tramadol', 'dextromethorphan', 'citalopram', 'escitalopram', 'mirtazapine', 'trazodone', 'bupropion', 'amitriptyline', 'clomipramine', 'nortriptyline', 'protriptyline', 'imipramine', 'phenelzine', 'isocarboxazid', 'selegiline', 'linezolid', 'methylene blue', 'pethidine', 'fentanyl', 'sufentanil', 'pindolol', 'buspirone', 'tianeptine') THEN 1 ELSE 0 END) AS serotonergic_risk,
    EXTRACT(DAY FROM (dischtime - admittime)) AS los_days,
    hospital_expire_flag
  FROM
    cohort
  GROUP BY
    subject_id, dischtime, admittime, hospital_expire_flag
  HAVING
    COUNT(DISTINCT drug) > 0
),
medication_complexity AS (
  SELECT
    AVG(num_meds) AS mean_meds,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY num_meds) AS p25,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY num_meds) AS p50,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY num_meds) AS p75
  FROM
    medication_data
),
los_mortality_comparison AS (
  SELECT
    serotonergic_risk,
    AVG(los_days) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    medication_data
  GROUP BY
    serotonergic_risk
),
top_quartile_los AS (
  SELECT
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los_days) AS top_quartile_los,
    AVG(hospital_expire_flag) AS mortality_top_quartile
  FROM
    medication_data
  WHERE
    los_days >= (SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los_days) FROM medication_data)
)
SELECT
  'mean_meds' AS metric,
  mean_meds AS value,
  NULL AS group_value
FROM
  medication_complexity
UNION ALL
SELECT
  'p25_meds',
  p25,
  NULL
FROM
  medication_complexity
UNION ALL
SELECT
  'p50_meds',
  p50,
  NULL
FROM
  medication_complexity
UNION ALL
SELECT
  'p75_meds',
  p75,
  NULL
FROM
  medication_complexity
UNION ALL
SELECT
  'avg_los_serotonergic',
  avg_los,
  'serotonergic'
FROM
  los_mortality_comparison
WHERE
  serotonergic_risk = 1
UNION ALL
SELECT
  'avg_los_non_serotonergic',
  avg_los,
  'non_serotonergic'
FROM
  los_mortality_comparison
WHERE
  serotonergic_risk = 0
UNION ALL
SELECT
  'mortality_serotonergic',
  mortality_rate,
  'serotonergic'
FROM
  los_mortality_comparison
WHERE
  serotonergic_risk = 1
UNION ALL
SELECT
  'mortality_non_serotonergic',
  mortality_rate,
  'non_serotonergic'
FROM
  los_mortality_comparison
WHERE
  serotonergic_risk = 0
UNION ALL
SELECT
  'top_quartile_los',
  top_quartile_los,
  NULL
FROM
  top_quartile_los
UNION ALL
SELECT
  'mortality_top_quartile',
  mortality_top_quartile,
  NULL
FROM
  top_quartile_los;