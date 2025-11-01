WITH ich_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND (
      dd.long_title LIKE '%intracranial hemorrhage%'
      OR di.icd_code IN ('430','431','432')
      OR di.icd_code LIKE 'I60%'
      OR di.icd_code LIKE 'I61%'
      OR di.icd_code LIKE 'I62%'
    )
),
comorbidity_count AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS n_comorbidities
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE NOT (
    icd_code IN ('430','431','432')
    OR icd_code LIKE 'I60%'
    OR icd_code LIKE 'I61%'
    OR icd_code LIKE 'I62%'
  )
  GROUP BY hadm_id
),
scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.hospital_expire_flag,
    c.los_days,
    IFNULL(cc.n_comorbidities,0) AS n_comorbidities,
    c.anchor_age + IFNULL(cc.n_comorbidities,0) AS composite_score
  FROM ich_cohort c
  LEFT JOIN comorbidity_count cc
    ON c.hadm_id = cc.hadm_id
),
quartiles AS (
  SELECT
    s.*,
    NTILE(4) OVER (ORDER BY composite_score) AS risk_quartile
  FROM scores s
),
complications AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    q.risk_quartile,
    MAX(CASE WHEN dd.long_title LIKE '%myocardial%' 
               OR dd.long_title LIKE '%cardiac arrest%'
               OR dd.long_title LIKE '%arrhythmia%'
               OR dd.long_title LIKE '%heart failure%' THEN 1 ELSE 0 END) AS cardiac_complication,
    MAX(CASE WHEN dd.long_title LIKE '%stroke%'
               OR dd.long_title LIKE '%cerebral edema%'
               OR dd.long_title LIKE '%seizure%'
               OR dd.long_title LIKE '%coma%' THEN 1 ELSE 0 END) AS neuro_complication
  FROM quartiles q
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON q.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY q.subject_id, q.hadm_id, q.risk_quartile
),
final AS (
  SELECT
    q.risk_quartile,
    COUNT(DISTINCT q.subject_id) AS patient_count,
    AVG(q.hospital_expire_flag)*100 AS in_hosp_mortality_pct,
    AVG(c.cardiac_complication)*100 AS cardiac_complication_pct,
    AVG(c.neuro_complication)*100 AS neurologic_complication_pct,
    APPROX_QUANTILES(q.los_days, 2)[OFFSET(1)] AS median_los_survivors
  FROM quartiles q
  JOIN complications c
    ON q.subject_id = c.subject_id AND q.hadm_id = c.hadm_id AND q.risk_quartile = c.risk_quartile
  WHERE q.hospital_expire_flag = 0 -- survivors for LOS
  GROUP BY q.risk_quartile
)
SELECT * FROM final
ORDER BY risk_quartile;