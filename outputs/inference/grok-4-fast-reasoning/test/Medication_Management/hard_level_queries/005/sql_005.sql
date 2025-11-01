WITH icd_cte AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%hepatic failure%' OR LOWER(long_title) LIKE '%liver failure%'
),
qualifying AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN icd_cte ic
    ON di.icd_code = ic.icd_code AND di.icd_version = ic.icd_version
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - 2008) BETWEEN 43 AND 53
),
scores AS (
  SELECT
    q.*,
    COUNT(DISTINCT pres.drug) AS score
  FROM qualifying q
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON q.subject_id = pres.subject_id
    AND q.hadm_id = pres.hadm_id
    AND pres.drug IS NOT NULL
    AND pres.drug != ''
    AND pres.starttime >= q.admittime
    AND pres.starttime < TIMESTAMP_ADD(q.admittime, INTERVAL 3 DAY)
  GROUP BY
    q.subject_id, q.hadm_id, q.admittime, q.dischtime, q.hospital_expire_flag
),
los_calc AS (
  SELECT
    *,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days
  FROM scores
),
readmits AS (
  SELECT
    l.*,
    CASE WHEN COUNT(a2.hadm_id) > 0 THEN 1 ELSE 0 END AS readmit_flag
  FROM los_calc l
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON l.subject_id = a2.subject_id
    AND a2.hadm_id != l.hadm_id
    AND a2.admittime > l.dischtime
    AND a2.admittime < TIMESTAMP_ADD(l.dischtime, INTERVAL 30 DAY)
  GROUP BY
    l.subject_id, l.hadm_id, l.admittime, l.dischtime, l.hospital_expire_flag,
    l.score, l.los_days
)
SELECT
  quintile,
  COUNT(*) AS n,
  MIN(score) AS min_score,
  MAX(score) AS max_score,
  ROUND(AVG(score), 2) AS mean_score,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(readmit_flag) * 100, 2) AS readmit_30d_pct
FROM (
  SELECT *, NTILE(5) OVER (ORDER BY score ASC) AS quintile
  FROM readmits
)
GROUP BY quintile
ORDER BY quintile;