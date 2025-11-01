WITH cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_type = 'trauma'
),

prescriptions_24h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    p.drug,
    p.starttime
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE
    p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL '24' HOUR
),

medication_complexity AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT drug) AS complexity_count,
    MAX(CASE WHEN drug IN (
      'sertraline', 'fluoxetine', 'citalopram', 'escitalopram', 'paroxetine',
      'venlafaxine', 'duloxetine', 'clomipramine', 'trazodone', 'mirtazapine',
      'tramadol', 'fentanyl', 'meperidine', 'methadone', 'dextromethorphan',
      'linezolid', 'methylene blue'
    ) THEN 1 ELSE 0 END) AS serotonergic_risk
  FROM
    prescriptions_24h
  GROUP BY
    subject_id, hadm_id
),

complexity_with_quartiles AS (
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.complexity_count,
    mc.serotonergic_risk,
    EXTRACT(DAY FROM (c.dischtime - c.admittime)) AS los_days,
    c.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY mc.complexity_count) AS complexity_quartile,
    PERCENT_RANK() OVER (ORDER BY mc.complexity_count) AS complexity_percentile
  FROM
    medication_complexity mc
  JOIN
    cohort c
    ON mc.subject_id = c.subject_id AND mc.hadm_id = c.hadm_id
)

SELECT
  'serotonergic' AS group_type,
  AVG(complexity_count) AS avg_complexity,
  AVG(complexity_percentile) AS avg_complexity_percentile,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM
  complexity_with_quartiles
WHERE
  serotonergic_risk = 1

UNION ALL

SELECT
  'non-serotonergic' AS group_type,
  AVG(complexity_count) AS avg_complexity,
  AVG(complexity_percentile) AS avg_complexity_percentile,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM
  complexity_with_quartiles
WHERE
  serotonergic_risk = 0

UNION ALL

SELECT
  'top_quartile' AS group_type,
  NULL AS avg_complexity,
  NULL AS avg_complexity_percentile,
  AVG(los_days) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM
  complexity_with_quartiles
WHERE
  complexity_quartile = 4;