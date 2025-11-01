WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    COUNT(d.icd_code) AS diagnosis_count,
    SUM(CASE WHEN d.seq_num > 1 AND maj_comp.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS major_complication_count
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  LEFT JOIN (
    -- List of major complications ICD codes (example subset)
    SELECT '4580' AS icd_code, 9 AS icd_version UNION ALL
    SELECT '78552', 9 UNION ALL
    SELECT '99592', 9 UNION ALL
    SELECT '51881', 9 UNION ALL
    SELECT '51882', 9 UNION ALL
    SELECT '4589', 9
  ) maj_comp
    ON d.icd_code = maj_comp.icd_code AND d.icd_version = maj_comp.icd_version
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND d.seq_num = 1
    AND LOWER(did.long_title) LIKE '%upper gastrointestinal bleeding%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag, p.anchor_age
),
risk_scores AS (
  SELECT
    *,
    diagnosis_count + 20 * major_complication_count AS composite_score,
    DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 AS los
  FROM
    cohort
),
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY composite_score) AS score_quintile
  FROM
    risk_scores
)
SELECT
  score_quintile,
  COUNT(*) AS n,
  AVG(composite_score) AS mean_score,
  ROUND(AVG(CASE WHEN DATETIME_DIFF(deathtime, admittime, DAY) <= 30 THEN 1 ELSE 0 END) * 100, 2) AS mortality_30d_pct,
  ROUND(AVG(CASE WHEN major_complication_count > 0 THEN 1 ELSE 0 END) * 100, 2) AS major_complication_pct,
  APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los ELSE NULL END, 100)[OFFSET(50)] AS median_survivor_los
FROM
  quintiles
GROUP BY
  score_quintile
ORDER BY
  score_quintile;