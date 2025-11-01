WITH cohort AS (
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id 
    AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
    ON d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND d.seq_num = 1
    AND LOWER(icd.long_title) LIKE '%pneumonia%'
),
lab_instability AS (
  SELECT 
    c.hadm_id,
    COUNT(CASE WHEN le.flag <> '' THEN 1 END) AS instability_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id
    AND c.hadm_id = le.hadm_id
    AND le.charttime >= c.admittime
    AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id
),
crit_per_hadm_cohort AS (
  SELECT 
    c.hadm_id,
    COUNT(ce.itemid) AS crit_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
    AND c.hadm_id = ce.hadm_id
    AND ce.warning > 0
  GROUP BY c.hadm_id
),
all_inpatients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
crit_per_hadm_all AS (
  SELECT 
    hadm_id,
    COUNT(itemid) AS crit_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE warning > 0
  GROUP BY hadm_id
),
agg_all_crit AS (
  SELECT 
    AVG(COALESCE(cpa.crit_count, 0)) AS mean_crit_all
  FROM all_inpatients ai
  LEFT JOIN crit_per_hadm_all cpa
    ON ai.hadm_id = cpa.hadm_id
)
SELECT 
  APPROX_QUANTILES(li.instability_score, 100)[OFFSET(75)] AS p75_lab_instability,
  AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0) AS mean_los_days,
  AVG(CAST(c.hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct,
  AVG(COALESCE(cpc.crit_count, 0)) AS mean_crit_cohort,
  aac.mean_crit_all
FROM cohort c
INNER JOIN lab_instability li 
  ON c.hadm_id = li.hadm_id
LEFT JOIN crit_per_hadm_cohort cpc 
  ON c.hadm_id = cpc.hadm_id
CROSS JOIN agg_all_crit aac;