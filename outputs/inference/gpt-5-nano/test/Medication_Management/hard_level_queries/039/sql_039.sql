WITH eligible AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- medication complexity score: count of unique drugs + unique routes within first 48 hours
    COALESCE(COUNT(DISTINCT p.drug), 0) + COALESCE(COUNT(DISTINCT p.route), 0) AS score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON p.hadm_id = a.hadm_id
   AND p.starttime >= a.admittime
   AND p.starttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON a.subject_id = pat.subject_id
  WHERE pat.gender = 'Female'
    AND pat.anchor_age BETWEEN 87 AND 97
    -- ICH: ICD-9 431 or ICD-10 I61% (intracerebral hemorrhage)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
              (di.icd_version = 9 AND di.icd_code = '431')
              OR (di.icd_version = 10 AND di.icd_code LIKE 'I61%')
            )
    )
  GROUP BY
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
),

quartile_scores AS (
  SELECT
    e.hadm_id,
    e.subject_id,
    e.admittime,
    e.dischtime,
    e.hospital_expire_flag,
    e.score,
    NTILE(4) OVER (ORDER BY e.score ASC) AS quartile
  FROM eligible AS e
),

readmit AS (
  SELECT
    w.hadm_id,
    w.subject_id,
    w.admittime,
    w.dischtime,
    w.hospital_expire_flag,
    w.score,
    w.quartile,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
        WHERE a2.subject_id = w.subject_id
          AND a2.hadm_id != w.hadm_id
          AND a2.admittime > w.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(w.dischtime, INTERVAL 30 DAY)
      ) THEN 1 ELSE 0 END AS is_readmit_30
  FROM quartile_scores AS w
),

quartile_list AS (
  SELECT 1 AS quartile UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
),

stats AS (
  SELECT
    q.quartile,
    COUNT(*) AS admissions,
    MIN(r.score) AS score_min,
    MAX(r.score) AS score_max,
    AVG(TIMESTAMP_DIFF(r.dischtime, r.admittime, SECOND) / 86400.0) AS avg_los_days,
    100.0 * SUM(CASE WHEN r.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS mortality_rate_pct,
    100.0 * AVG(r.is_readmit_30) AS readmission_30d_rate_pct
  FROM quartile_list AS q
  LEFT JOIN readmit AS r
    ON q.quartile = r.quartile
  GROUP BY q.quartile
)

SELECT
  q.quartile,
  COALESCE(s.admissions, 0) AS admissions,
  s.score_min,
  s.score_max,
  s.avg_los_days,
  s.mortality_rate_pct,
  s.readmission_30d_rate_pct
FROM quartile_list AS q
LEFT JOIN stats AS s
  ON q.quartile = s.quartile
ORDER BY q.quartile;