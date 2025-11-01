WITH sepsis_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE
        a.hadm_id = d.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '038%')
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%'))
        )
    )
),
qt_drugs AS (
  SELECT 'amiodarone' AS drug_name UNION ALL
  SELECT 'moxifloxacin' UNION ALL
  SELECT 'ciprofloxacin' UNION ALL
  SELECT 'levofloxacin' UNION ALL
  SELECT 'haloperidol' UNION ALL
  SELECT 'ziprasidone' UNION ALL
  SELECT 'ondansetron' UNION ALL
  SELECT 'dofetilide' UNION ALL
  SELECT 'sotalol' UNION ALL
  SELECT 'quinidine'
),
bleed_drugs AS (
  SELECT 'warfarin' AS drug_name UNION ALL
  SELECT 'heparin' UNION ALL
  SELECT 'enoxaparin' UNION ALL
  SELECT 'aspirin' UNION ALL
  SELECT 'clopidogrel' UNION ALL
  SELECT 'ticagrelor' UNION ALL
  SELECT 'dabigatran' UNION ALL
  SELECT 'rivaroxaban' UNION ALL
  SELECT 'apixaban' UNION ALL
  SELECT 'prasugrel'
),
both_drugs_flag AS (
  SELECT
    s.hadm_id,
    MAX(CASE WHEN q.drug_name IS NOT NULL THEN 1 ELSE 0 END) AS has_qt,
    MAX(CASE WHEN b.drug_name IS NOT NULL THEN 1 ELSE 0 END) AS has_bleed
  FROM
    sepsis_cohort s
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON s.hadm_id = p.hadm_id
    AND p.starttime >= s.admittime
    AND p.starttime <= s.admittime + INTERVAL '24' HOUR
  LEFT JOIN
    qt_drugs q
    ON p.drug = q.drug_name
  LEFT JOIN
    bleed_drugs b
    ON p.drug = b.drug_name
  GROUP BY
    s.hadm_id
),
complexity_score AS (
  SELECT
    s.hadm_id,
    COUNT(DISTINCT p.drug) AS complexity_score
  FROM
    sepsis_cohort s
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON s.hadm_id = p.hadm_id
    AND p.starttime >= s.admittime
    AND p.starttime <= s.admittime + INTERVAL '24' HOUR
  GROUP BY
    s.hadm_id
),
quartile AS (
  SELECT
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY complexity_score) AS top_quartile
  FROM
    complexity_score
),
combined AS (
  SELECT
    s.hadm_id,
    s.admittime,
    s.dischtime,
    s.hospital_expire_flag,
    b.has_qt,
    b.has_bleed,
    c.complexity_score,
    CASE WHEN b.has_qt = 1 AND b.has_bleed = 1 THEN 1 ELSE 0 END AS both_drugs
  FROM
    sepsis_cohort s
  LEFT JOIN
    both_drugs_flag b
    ON s.hadm_id = b.hadm_id
  LEFT JOIN
    complexity_score c
    ON s.hadm_id = c.hadm_id
)
-- Medication complexity score distribution by group
SELECT
  both_drugs,
  AVG(complexity_score) AS mean_score,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY complexity_score) AS q1,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY complexity_score) AS median,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY complexity_score) AS q3,
  COUNT(*) AS count
FROM
  combined
GROUP BY
  both_drugs

UNION ALL

-- LOS and mortality for top quartile
SELECT
  'top_quartile' AS group_name,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM
  combined,
  quartile
WHERE
  complexity_score >= top_quartile;