WITH elixhauser_codes AS (
  SELECT icd_code
  FROM physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses
  WHERE icd_version = 10
    AND (
      long_title LIKE '%heart failure%' OR
      long_title LIKE '%peripheral vascular disease%' OR
      long_title LIKE '%hypertension%' OR
      long_title LIKE '%paralysis%' OR
      long_title LIKE '%other neurological disorders%' OR
      long_title LIKE '%chronic pulmonary disease%' OR
      long_title LIKE '%rheumatic disease%' OR
      long_title LIKE '%peptic ulcer disease%' OR
      long_title LIKE '%mild liver disease%' OR
      long_title LIKE '%diabetes without complications%' OR
      long_title LIKE '%diabetes with complications%' OR
      long_title LIKE '%renal failure%' OR
      long_title LIKE '%cancer%' OR
      long_title LIKE '%metastatic cancer%' OR
      long_title LIKE '%solid tumor without metastasis%' OR
      long_title LIKE '%aids/hiv%' OR
      long_title LIKE '%lymphoma%' OR
      long_title LIKE '%coagulopathy%' OR
      long_title LIKE '%obesity%' OR
      long_title LIKE '%weight loss%' OR
      long_title LIKE '%fluid and electrolyte disorders%' OR
      long_title LIKE '%blood loss anemia%' OR
      long_title LIKE '%deficiency anemia%' OR
      long_title LIKE '%alcohol abuse%' OR
      long_title LIKE '%drug abuse%' OR
      long_title LIKE '%psychoses%' OR
      long_title LIKE '%depression%'
    )
),

complication_codes AS (
  SELECT icd_code
  FROM physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses
  WHERE icd_version = 10
    AND (
      long_title LIKE '%sepsis%' OR
      long_title LIKE '%acute respiratory failure%' OR
      long_title LIKE '%cardiac arrest%' OR
      long_title LIKE '%acute kidney injury%' OR
      long_title LIKE '%shock%' OR
      long_title LIKE '%pulmonary embolism%' OR
      long_title LIKE '%stroke%' OR
      long_title LIKE '%myocardial infarction%' OR
      long_title LIKE '%major bleeding%' 
    )
  UNION ALL
  SELECT icd_code
  FROM physionet-data.mimiciv_3_1_hosp.d_icd_procedures
  WHERE icd_version = 10
    AND (
      long_title LIKE '%tracheostomy%' OR
      long_title LIKE '%extracorporeal membrane oxygenation%' OR
      long_title LIKE '%intra-aortic balloon pump%'
    )
),

pneumonia_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND LOWER(di.long_title) LIKE '%pneumonia%'
),

comorbidity_counts AS (
  SELECT pp.subject_id, pp.hadm_id, pp.admittime, pp.dischtime, pp.deathtime, pp.hospital_expire_flag,
         COUNT(DISTINCT ec.icd_code) AS elixhauser_count
  FROM pneumonia_patients pp
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON pp.subject_id = d.subject_id AND pp.hadm_id = d.hadm_id
  JOIN elixhauser_codes ec ON d.icd_code = ec.icd_code
  GROUP BY pp.subject_id, pp.hadm_id, pp.admittime, pp.dischtime, pp.deathtime, pp.hospital_expire_flag
),

top_quartile_threshold AS (
  SELECT PERCENTILE_CONT(elixhauser_count, 0.75) OVER () AS q75
  FROM comorbidity_counts
),

cohort AS (
  SELECT cc.*
  FROM comorbidity_counts cc
  CROSS JOIN top_quartile_threshold tqt
  WHERE cc.elixhauser_count >= tqt.q75
),

complication_flag AS (
  SELECT DISTINCT c.subject_id, c.hadm_id,
         CASE WHEN COUNT(cc.icd_code) > 0 THEN 1 ELSE 0 END AS has_major_complication
  FROM cohort c
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON c.hadm_id = d.hadm_id
  LEFT JOIN complication_codes cc ON d.icd_code = cc.icd_code
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd p ON c.hadm_id = p.hadm_id
  LEFT JOIN complication_codes ccp ON p.icd_code = ccp.icd_code
  GROUP BY c.subject_id, c.hadm_id
),

survival_days AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.hospital_expire_flag,
    TIMESTAMP_DIFF(COALESCE(c.deathtime, c.dischtime), c.admittime, DAY) AS survival_days
  FROM cohort c
)

SELECT
  ROUND(100.0 * SUM(CASE WHEN sd.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS in_hospital_mortality_percent,
  ROUND(100.0 * SUM(cf.has_major_complication) / COUNT(*), 2) AS major_complication_percent,
  PERCENTILE_CONT(sd.survival_days, 0.5) AS median_survival_days
FROM survival_days sd
JOIN complication_flag cf ON sd.subject_id = cf.subject_id AND sd.hadm_id = cf.hadm_id;