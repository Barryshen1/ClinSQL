WITH pe_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.dod,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND di.long_title LIKE '%pulmonary embolism%'
  GROUP BY p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, p.dod
),
top_quartile AS (
  SELECT
    subject_id,
    hadm_id,
    comorbidity_count,
    NTILE(4) OVER (ORDER BY comorbidity_count DESC) AS quartile
  FROM pe_patients
),
top_quartile_group AS (
  SELECT *
  FROM top_quartile
  WHERE quartile = 1
),
specific_patient AS (
  SELECT subject_id
  FROM pe_patients
  WHERE anchor_age = 84 AND gender = 'M'
),
mortality AS (
  SELECT
    AVG(CASE WHEN p.dod IS NOT NULL AND DATE_DIFF(p.dod, a.admittime, DAY) <= 30 THEN 1 ELSE 0 END) * 100 AS thirty_day_mortality_rate
  FROM top_quartile_group t
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON t.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON t.subject_id = p.subject_id
),
cardiac_complications AS (
  SELECT
    COUNT(DISTINCT CASE WHEN di.long_title LIKE '%myocardial infarction%' OR di.long_title LIKE '%heart failure%' THEN d.subject_id END) * 100.0 / COUNT(DISTINCT t.subject_id) AS cardiac_complication_rate
  FROM top_quartile_group t
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON t.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
),
neuro_complications AS (
  SELECT
    COUNT(DISTINCT CASE WHEN di.long_title LIKE '%stroke%' OR di.long_title LIKE '%cerebrovascular accident%' THEN d.subject_id END) * 100.0 / COUNT(DISTINCT t.subject_id) AS neuro_complication_rate
  FROM top_quartile_group t
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON t.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
),
survival_days AS (
  SELECT
    CASE 
      WHEN p.dod IS NOT NULL THEN DATE_DIFF(p.dod, a.admittime, DAY)
      ELSE 30
    END AS survival_days
  FROM top_quartile_group t
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON t.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON t.subject_id = p.subject_id
)
SELECT
  (SELECT PERCENT_RANK() OVER (ORDER BY comorbidity_count) * 100 FROM top_quartile_group WHERE subject_id = (SELECT subject_id FROM specific_patient)) AS composite_risk_score_percentile,
  (SELECT thirty_day_mortality_rate FROM mortality) AS thirty_day_mortality_rate,
  (SELECT cardiac_complication_rate FROM cardiac_complications) AS cardiac_complication_rate,
  (SELECT neuro_complication_rate FROM neuro_complications) AS neuro_complication_rate,
  (SELECT APPROX_QUANTILES(survival_days, 100)[OFFSET(50)] FROM survival_days) AS median_survival_days;