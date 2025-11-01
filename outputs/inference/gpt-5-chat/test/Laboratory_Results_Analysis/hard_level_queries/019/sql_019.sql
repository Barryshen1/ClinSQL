WITH cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND LOWER(dd.long_title) LIKE '%acute pancreatitis%'
),
lab_scores AS (
  SELECT c.subject_id, c.hadm_id,
         COUNTIF(l.flag IS NOT NULL) AS instability_score
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.subject_id = l.subject_id
    AND c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),
p90_value AS (
  SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score
  FROM lab_scores
),
high_instability AS (
  SELECT ls.subject_id, ls.hadm_id, ls.instability_score, c.admittime, c.dischtime, c.hospital_expire_flag
  FROM lab_scores ls
  JOIN cohort c
    ON ls.subject_id = c.subject_id
    AND ls.hadm_id = c.hadm_id
  CROSS JOIN p90_value p
  WHERE ls.instability_score >= p.p90_score
),
hi_per_lab AS (
  SELECT l.itemid,
         COUNTIF(l.flag IS NOT NULL) / COUNT(*) AS hi_critical_rate
  FROM high_instability h
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON h.subject_id = l.subject_id
    AND h.hadm_id = l.hadm_id
    AND l.charttime BETWEEN h.admittime AND TIMESTAMP_ADD(h.admittime, INTERVAL 72 HOUR)
  GROUP BY l.itemid
),
all_inpatients AS (
  SELECT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
all_per_lab AS (
  SELECT l.itemid,
         COUNTIF(l.flag IS NOT NULL) / COUNT(*) AS all_critical_rate
  FROM all_inpatients ai
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON ai.subject_id = l.subject_id
    AND ai.hadm_id = l.hadm_id
    AND l.charttime BETWEEN ai.admittime AND TIMESTAMP_ADD(ai.admittime, INTERVAL 72 HOUR)
  GROUP BY l.itemid
)
SELECT 
  p.p90_score,
  AVG(CASE WHEN h.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate_hi,
  AVG(DATE_DIFF(h.dischtime, h.admittime, DAY)) AS mean_los_hi_days,
  di.label AS lab_label,
  hi.hi_critical_rate,
  allp.all_critical_rate
FROM p90_value p
JOIN high_instability h ON TRUE
JOIN hi_per_lab hi
  ON TRUE
JOIN all_per_lab allp
  ON hi.itemid = allp.itemid
LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
  ON hi.itemid = di.itemid
GROUP BY p.p90_score, di.label, hi.hi_critical_rate, allp.all_critical_rate
ORDER BY hi.hi_critical_rate DESC;