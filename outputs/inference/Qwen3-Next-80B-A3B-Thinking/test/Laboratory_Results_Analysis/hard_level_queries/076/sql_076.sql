WITH cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '411%' OR d.icd_code LIKE '413%' OR d.icd_code LIKE '414%'))
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I23%' OR d.icd_code LIKE 'I24%' OR d.icd_code LIKE 'I25%'))
    )
),
lab_scores AS (
  SELECT c.subject_id, c.hadm_id,
         COUNT(l.labevent_id) AS lab_instability_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime >= c.admittime
    AND l.charttime <= c.admittime + INTERVAL 72 HOUR
    AND l.flag IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id
),
percentile AS (
  SELECT PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY lab_instability_score) AS p95
  FROM lab_scores
)
SELECT 
  AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR)/24) AS mean_los_days,
  AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
  AVG(ls.lab_instability_score) AS avg_critical_lab_events_high,
  (SELECT AVG(lab_instability_score) FROM lab_scores) AS avg_critical_lab_events_all
FROM lab_scores ls
JOIN cohort c ON ls.subject_id = c.subject_id AND ls.hadm_id = c.hadm_id
WHERE ls.lab_instability_score >= (SELECT p95 FROM percentile);