WITH ami_cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
         p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
      OR (d.icd_version = 9 AND d.icd_code LIKE '410%')
    )
),
complexity AS (
  SELECT ac.subject_id, ac.hadm_id,
         COALESCE(COUNT(DISTINCT e.medication),0) AS complexity_score
  FROM ami_cohort ac
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON ac.subject_id = e.subject_id
    AND ac.hadm_id = e.hadm_id
    AND e.charttime BETWEEN ac.admittime AND TIMESTAMP_ADD(ac.admittime, INTERVAL 24 HOUR)
  GROUP BY ac.subject_id, ac.hadm_id
),
los_mortality AS (
  SELECT ac.subject_id, ac.hadm_id,
         TIMESTAMP_DIFF(ac.dischtime, ac.admittime, DAY) AS los_days,
         a.hospital_expire_flag
  FROM ami_cohort ac
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ac.hadm_id = a.hadm_id
),
readmission_flag AS (
  SELECT ac.subject_id, ac.hadm_id,
         CASE WHEN COUNT(r.hadm_id) > 0 THEN 1 ELSE 0 END AS readmit_30d
  FROM ami_cohort ac
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` r
    ON ac.subject_id = r.subject_id
    AND r.hadm_id != ac.hadm_id
    AND r.admittime > ac.dischtime
    AND r.admittime <= TIMESTAMP_ADD(ac.dischtime, INTERVAL 30 DAY)
  GROUP BY ac.subject_id, ac.hadm_id
),
full_data AS (
  SELECT c.subject_id, c.hadm_id, c.complexity_score,
         l.los_days, l.hospital_expire_flag, r.readmit_30d
  FROM complexity c
  JOIN los_mortality l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  JOIN readmission_flag r
    ON c.subject_id = r.subject_id AND c.hadm_id = r.hadm_id
),
tertiles AS (
  SELECT *,
         NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM full_data
)
SELECT tertile,
       COUNT(*) AS admission_count,
       MIN(complexity_score) AS score_min,
       MAX(complexity_score) AS score_max,
       ROUND(AVG(complexity_score),2) AS score_mean,
       ROUND(AVG(los_days),2) AS mean_los_days,
       ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*),2) AS in_hosp_mortality_pct,
       ROUND(100.0 * SUM(readmit_30d) / COUNT(*),2) AS readmit_30d_pct
FROM tertiles
GROUP BY tertile
ORDER BY tertile;