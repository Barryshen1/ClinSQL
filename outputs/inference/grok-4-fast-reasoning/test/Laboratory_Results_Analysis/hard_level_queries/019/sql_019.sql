WITH cohort_ap AS (
  SELECT DISTINCT
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di 
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND di.icd_version = 10
    AND di.icd_code LIKE 'K85%'
),
general_cohort AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
),
scores_ap AS (
  SELECT 
    c.hadm_id,
    COUNT(CASE WHEN le.flag != '' THEN 1 END) AS instability_score
  FROM cohort_ap c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le 
    ON c.hadm_id = le.hadm_id
    AND le.charttime >= c.admittime
    AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id
),
p90 AS (
  SELECT PERCENTILE_CONT(instability_score, 0.9) AS p90_score
  FROM scores_ap
),
subgroup_hadms AS (
  SELECT s.hadm_id
  FROM scores_ap s
  CROSS JOIN p90
  WHERE s.instability_score >= p90.p90_score
),
subgroup_metrics AS (
  SELECT 
    (SUM(CAST(hospital_expire_flag AS INT64)) * 1.0 / COUNT(*)) AS mortality,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days
  FROM cohort_ap c
  INNER JOIN subgroup_hadms sh ON c.hadm_id = sh.hadm_id
),
key_labs AS (
  SELECT DISTINCT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp`.d_labitems
  WHERE label LIKE '%LIPASE%'
     OR label LIKE '%AMYLASE%'
     OR label LIKE '%GLUCOSE%'
     OR label LIKE '%SODIUM%'
     OR label LIKE '%POTASSIUM%'
     OR label LIKE '%BUN%'
     OR label LIKE '%CREATININE%'
     OR label LIKE '%WBC%'
     OR label LIKE '%ALT%'
     OR label LIKE '%AST%'
     OR label LIKE '%BILIRUBIN%'
     OR label LIKE '%CRP%'
),
sub_lab_rates AS (
  SELECT 
    kl.label,
    SAFE_DIVIDE(SUM(CASE WHEN le.flag != '' THEN 1 ELSE 0 END), COUNT(le.labevent_id)) AS critical_rate
  FROM cohort_ap c
  INNER JOIN subgroup_hadms sh ON c.hadm_id = sh.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le 
    ON c.hadm_id = le.hadm_id
    AND le.charttime >= c.admittime
    AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  INNER JOIN key_labs kl ON le.itemid = kl.itemid
  GROUP BY kl.label
),
gen_lab_rates AS (
  SELECT 
    kl.label,
    SAFE_DIVIDE(SUM(CASE WHEN le.flag != '' THEN 1 ELSE 0 END), COUNT(le.labevent_id)) AS critical_rate
  FROM general_cohort gc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le 
    ON gc.hadm_id = le.hadm_id
    AND le.charttime >= gc.admittime
    AND le.charttime < TIMESTAMP_ADD(gc.admittime, INTERVAL 72 HOUR)
  INNER JOIN key_labs kl ON le.itemid = kl.itemid
  GROUP BY kl.label
),
rates AS (
  SELECT 
    COALESCE(s.label, g.label) AS label,
    IFNULL(s.critical_rate, 0.0) AS sub_rate,
    IFNULL(g.critical_rate, 0.0) AS gen_rate
  FROM sub_lab_rates s
  FULL OUTER JOIN gen_lab_rates g ON s.label = g.label
)
SELECT '90th Percentile Score' AS metric, 
       CAST(p90.p90_score AS STRING) AS value, 
       NULL AS comparison
FROM p90
UNION ALL
SELECT 'Subgroup Mortality' AS metric, 
       FORMAT('%.4f', sm.mortality) AS value, 
       NULL AS comparison
FROM subgroup_metrics sm
UNION ALL
SELECT 'Subgroup Mean LOS (days)' AS metric, 
       FORMAT('%.2f', sm.mean_los_days) AS value, 
       NULL AS comparison
FROM subgroup_metrics sm
UNION ALL
SELECT CONCAT('Critical Rate - ', r.label) AS metric, 
       FORMAT('%.4f', r.sub_rate) AS value, 
       FORMAT('%.4f', r.gen_rate) AS comparison
FROM rates r
ORDER BY metric;