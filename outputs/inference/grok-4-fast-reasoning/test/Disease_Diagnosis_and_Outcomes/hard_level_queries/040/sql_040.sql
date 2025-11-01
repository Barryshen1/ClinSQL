WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.dod,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND (
      (d.icd_version = 9 AND d.icd_code = '431')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I61%')
    )
),
risk AS (
  SELECT
    c.*,
    COUNT(DISTINCT d.icd_code) AS risk_score
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
  GROUP BY
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.deathtime,
    c.hospital_expire_flag, c.dod, c.anchor_age
),
outcomes AS (
  SELECT
    r.*,
    CASE
      WHEN r.deathtime IS NOT NULL
        AND TIMESTAMP_DIFF(r.deathtime, r.admittime, DAY) <= 30 THEN 1
      WHEN r.deathtime IS NULL AND r.dod IS NOT NULL
        AND DATE_DIFF(r.dod, DATE(r.admittime), DAY) <= 30 THEN 1
      ELSE 0
    END AS died_30d,
    TIMESTAMP_DIFF(r.dischtime, r.admittime, HOUR) / 24.0 AS los_days,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
      WHERE pi.subject_id = r.subject_id
        AND pi.hadm_id = r.hadm_id
        AND (
          (pi.icd_version = 9 AND pi.icd_code LIKE '96.7%')
          OR
          (pi.icd_version = 10 AND (pi.icd_code LIKE '5A19%' OR pi.icd_code LIKE '5A15%'))
        )
    ) AS major_comp
  FROM risk r
),
quintiled AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM outcomes
)
SELECT
  quintile,
  COUNT(*) AS n,
  ROUND(100.0 * AVG(died_30d), 2) AS `30-day mortality %`,
  ROUND(100.0 * AVG(CAST(major_comp AS INT64)), 2) AS `major complication %`,
  APPROX_QUANTILES(
    CASE WHEN died_30d = 0 THEN los_days END,
    2
  )[SAFE_OFFSET(1)] AS `median survivor LOS (days)`
FROM quintiled
GROUP BY quintile
ORDER BY quintile;