WITH fem_59_69 AS (
  SELECT p.subject_id, p.gender, p.anchor_age, p.anchor_year, p.dod,
         a.hadm_id, a.admittime, a.dischtime, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),
dvt_hadm AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%deep vein thrombosis%'
     OR LOWER(dd.long_title) LIKE '%dvt%'
),
cohort AS (
  SELECT f.*, 
         COALESCE(p.dod, f.deathtime) AS death_date
  FROM fem_59_69 f
  JOIN dvt_hadm dv ON f.subject_id = dv.subject_id AND f.hadm_id = dv.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON f.subject_id = p.subject_id
),
comorb_counts AS (
  SELECT c.subject_id, c.hadm_id,
         COUNT(DISTINCT d.icd_code) AS comorb_count
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE NOT (LOWER(dd.long_title) LIKE '%deep vein thrombosis%' OR LOWER(dd.long_title) LIKE '%dvt%')
  GROUP BY c.subject_id, c.hadm_id
),
p75 AS (
  SELECT APPROX_QUANTILES(comorb_count,4)[OFFSET(3)] AS p75_comorb
  FROM comorb_counts
),
high_comorb AS (
  SELECT c.*, cc.comorb_count
  FROM cohort c
  JOIN comorb_counts cc USING (subject_id, hadm_id)
  CROSS JOIN p75
  WHERE cc.comorb_count >= p75.p75_comorb
),
complications AS (
  SELECT DISTINCT hadm_id,
    CASE WHEN COUNTIF(LOWER(dd.long_title) LIKE '%pulmonary embolism%'
                      OR LOWER(dd.long_title) LIKE '%stroke%'
                      OR LOWER(dd.long_title) LIKE '%myocardial infarction%'
                      OR LOWER(dd.long_title) LIKE '%sepsis%') > 0 THEN 1 ELSE 0 END AS major_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  GROUP BY hadm_id
),
risk_quartiles AS (
  SELECT hadm_id, comorb_count,
         NTILE(4) OVER (ORDER BY comorb_count) AS risk_quartile
  FROM high_comorb
)
SELECT
  COUNT(DISTINCT hc.subject_id) AS cohort_size,
  AVG(CASE WHEN hc.death_date IS NOT NULL 
             AND DATETIME_DIFF(hc.death_date, hc.admittime, DAY) <= 30 
           THEN 1 ELSE 0 END) AS mortality_30d_rate,
  AVG(COALESCE(comp.major_complication,0)) AS major_complication_rate,
  APPROX_QUANTILES(DATETIME_DIFF(hc.death_date, hc.admittime, DAY), 2)[OFFSET(1)] 
      AS median_survival_days_decedents,
  APPROX_QUANTILES(rq.comorb_count, 4) AS comorb_count_quartiles
FROM high_comorb hc
LEFT JOIN complications comp USING (hadm_id)
LEFT JOIN risk_quartiles rq USING (hadm_id)
WHERE hc.death_date IS NULL 
      OR DATETIME_DIFF(hc.death_date, hc.admittime, DAY) >= 0
;