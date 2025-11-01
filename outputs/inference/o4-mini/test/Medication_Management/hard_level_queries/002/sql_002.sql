WITH am_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.subject_id = di.subject_id
      AND a.hadm_id    = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code    = dd.icd_code
      AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
),
med_complexity AS (
  SELECT
    c.hadm_id,
    COALESCE(COUNT(DISTINCT pr.drug), 0) AS complexity_score
  FROM
    am_cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON c.subject_id = pr.subject_id
      AND c.hadm_id   = pr.hadm_id
      AND pr.starttime >= c.admittime
      AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY
    c.hadm_id
),
cohort_metrics AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    mc.complexity_score,
    DATE_DIFF(DATE(c.dischtime), DATE(c.admittime), DAY) AS los_days,
    c.hospital_expire_flag,
    -- 30-day readmission flag
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = c.subject_id
        AND a2.hadm_id != c.hadm_id
        AND a2.admittime > c.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
    ) AS readmit30_flag
  FROM
    am_cohort c
    JOIN med_complexity mc
      ON c.hadm_id = mc.hadm_id
),
ranked AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM
    cohort_metrics
)
SELECT
  tertile,
  COUNT(*) AS admissions,
  MIN(complexity_score) AS score_min,
  MAX(complexity_score) AS score_max,
  ROUND(AVG(complexity_score), 2) AS score_mean,
  ROUND(AVG(los_days), 2) AS los_mean_days,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 1) AS in_hospital_mortality_pct,
  ROUND(100.0 * SUM(CAST(readmit30_flag AS INT64)) / COUNT(*), 1) AS readmit30_pct
FROM
  ranked
GROUP BY
  tertile
ORDER BY
  tertile;