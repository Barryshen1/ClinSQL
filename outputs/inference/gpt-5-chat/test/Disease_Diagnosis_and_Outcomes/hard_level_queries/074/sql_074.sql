WITH pe_cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND LOWER(dd.long_title) LIKE '%pulmonary embolism%'
),
comorb_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM pe_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),
q3_val AS (
  SELECT
    APPROX_QUANTILES(comorbidity_count, 4)[OFFSET(3)] AS q3
  FROM comorb_counts
),
top_quartile AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.gender,
    c.admittime,
    c.dischtime,
    c.deathtime,
    c.hospital_expire_flag,
    cc.comorbidity_count,
    -- Composite risk score definition
    (c.anchor_age + cc.comorbidity_count * 2 + c.hospital_expire_flag * 10) AS risk_score
  FROM pe_cohort c
  JOIN comorb_counts cc
    ON c.hadm_id = cc.hadm_id
  CROSS JOIN q3_val
  WHERE cc.comorbidity_count >= q3_val.q3
),
percentiles AS (
  SELECT
    t.*,
    PERCENT_RANK() OVER (ORDER BY risk_score) AS risk_score_percentile
  FROM top_quartile t
),
complications AS (
  SELECT
    tq.subject_id,
    tq.hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%myocardial infarction%'
               OR LOWER(dd.long_title) LIKE '%heart failure%'
               OR LOWER(dd.long_title) LIKE '%arrhythmia%' THEN 1 ELSE 0 END) AS cardiac_flag,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%stroke%'
               OR LOWER(dd.long_title) LIKE '%seizure%' THEN 1 ELSE 0 END) AS neuro_flag
  FROM top_quartile tq
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON tq.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  GROUP BY tq.subject_id, tq.hadm_id
),
outcomes AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.anchor_age,
    p.risk_score_percentile,
    -- 30-day mortality flag
    CASE WHEN p.deathtime IS NOT NULL
              AND DATETIME_DIFF(p.deathtime, p.admittime, DAY) <= 30
         THEN 1 ELSE 0 END AS death_30day_flag,
    c.cardiac_flag,
    c.neuro_flag,
    -- Survival days (only if died)
    CASE WHEN p.deathtime IS NOT NULL
         THEN DATETIME_DIFF(p.deathtime, p.admittime, DAY)
         END AS survival_days
  FROM percentiles p
  LEFT JOIN complications c
    ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
),
summary AS (
  SELECT
    AVG(death_30day_flag) AS mortality_30day_rate,
    AVG(cardiac_flag) AS cardiac_complication_rate,
    AVG(neuro_flag) AS neuro_complication_rate,
    APPROX_QUANTILES(survival_days, 2)[OFFSET(1)] AS median_survival_days
  FROM outcomes
)
SELECT
  o.subject_id,
  o.hadm_id,
  o.risk_score_percentile,
  s.mortality_30day_rate,
  s.cardiac_complication_rate,
  s.neuro_complication_rate,
  s.median_survival_days
FROM outcomes o
CROSS JOIN summary s
WHERE o.anchor_age = 84;