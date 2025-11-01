WITH ich_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING(subject_id, hadm_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND d.icd_version = 9
    AND d.icd_code = '431'
),
lab_abnormal AS (
  SELECT
    ic.hadm_id,
    COUNT(DISTINCT le.itemid) AS instability_score
  FROM
    ich_cohort ic
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON ic.subject_id = le.subject_id
      AND ic.hadm_id     = le.hadm_id
      AND le.charttime BETWEEN ic.admittime
                          AND TIMESTAMP_ADD(ic.admittime, INTERVAL 48 HOUR)
  WHERE
    SAFE_CAST(le.valuenum AS FLOAT64) IS NOT NULL
    AND (
      le.valuenum < le.ref_range_lower
      OR le.valuenum > le.ref_range_upper
    )
  GROUP BY
    ic.hadm_id
),
ich_with_score AS (
  -- left join to give zero score if no abnormal labs
  SELECT
    ic.*,
    COALESCE(la.instability_score, 0) AS instability_score
  FROM
    ich_cohort ic
    LEFT JOIN lab_abnormal la USING(hadm_id)
),
ich_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS score_quartile
  FROM
    ich_with_score
),
quartile_summary AS (
  SELECT
    score_quartile,
    COUNT(*)                            AS n_admissions,
    ROUND(AVG(los_days), 2)            AS mean_los_days,
    ROUND(AVG(hospital_expire_flag), 3) AS mortality_rate
  FROM
    ich_quartiles
  GROUP BY
    score_quartile
  ORDER BY
    score_quartile
),
overall_mortality AS (
  SELECT
    'All male 73–83 inpatients' AS group_label,
    COUNT(*)                            AS n_admissions,
    ROUND(AVG(hospital_expire_flag), 3) AS mortality_rate
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
)
-- Final output: quartile summary plus overall comparator
SELECT
  CAST(score_quartile AS STRING) AS group_label,
  n_admissions,
  mean_los_days,
  mortality_rate
FROM
  quartile_summary

UNION ALL

SELECT
  group_label,
  n_admissions,
  NULL         AS mean_los_days,
  mortality_rate
FROM
  overall_mortality;