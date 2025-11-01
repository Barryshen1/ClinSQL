WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.dod AS dod,
    a.admission_type,
    p.anchor_age,
    p.gender,
    MAX(CASE
          WHEN LOWER(dll.long_title) LIKE '%copd%' AND LOWER(dll.long_title) LIKE '%exacerbat%'
            THEN 1 ELSE 0 END) AS copd_exac_present,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count,
    MAX(CASE
          WHEN LOWER(dll.long_title) LIKE '%sepsis%'
               OR LOWER(dll.long_title) LIKE '%acute kidney%'
               OR (LOWER(dll.long_title) LIKE '%kidney%' AND LOWER(dll.long_title) LIKE '%failure%')
               OR LOWER(dll.long_title) LIKE '%myocardial infarction%'
               OR LOWER(dll.long_title) LIKE '%stroke%'
               OR LOWER(dll.long_title) LIKE '%respiratory failure%'
               OR LOWER(dll.long_title) LIKE '%ARDS%'
               OR LOWER(dll.long_title) LIKE '%pneumonia%'
             THEN 1 ELSE 0 END) AS major_comp_present
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dll
    ON d.icd_code = dll.icd_code AND d.icd_version = dll.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
  GROUP BY
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.dod,
    a.admission_type,
    p.anchor_age,
    p.gender
),
cohort_filtered AS (
  SELECT * FROM cohort WHERE copd_exac_present = 1
),
cohort_scores AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    dod,
    admission_type,
    anchor_age,
    copd_exac_present,
    comorbidity_count,
    major_comp_present,
    (CASE WHEN anchor_age >= 80 THEN 2 ELSE 1 END)
      + 2 * copd_exac_present
      + 0.5 * comorbidity_count
      + (CASE WHEN admission_type = 'EMERGENCY' THEN 1.0 ELSE 0 END) AS risk_score,
    CASE WHEN dod IS NOT NULL AND DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 90 THEN 1 ELSE 0 END AS death90,
    DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) AS los_days
  FROM cohort_filtered
),
cohort_quart AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    dod,
    admission_type,
    anchor_age,
    copd_exac_present,
    comorbidity_count,
    major_comp_present,
    risk_score,
    death90,
    los_days,
    NTILE(4) OVER (ORDER BY risk_score) AS quartile
  FROM cohort_scores
),
quartile_metrics AS (
  SELECT
    quartile,
    CASE quartile WHEN 1 THEN 'Q1' WHEN 2 THEN 'Q2' WHEN 3 THEN 'Q3' ELSE 'Q4' END AS quartile_label,
    AVG(death90) AS mortality_90d_rate,
    AVG(CAST(major_comp_present AS FLOAT64)) AS major_comp_rate
  FROM cohort_quart
  GROUP BY quartile
),
median_subsurvivor AS (
  SELECT
    quartile,
    APPROX_QUANTILES(los_days_survivor, 100)[OFFSET(50)] AS median_survivor_los
  FROM (
    SELECT quartile, CASE WHEN death90 = 0 THEN los_days ELSE NULL END AS los_days_survivor
    FROM cohort_quart
  ) s
  GROUP BY quartile
)
SELECT
  qm.quartile_label,
  qm.mortality_90d_rate,
  qm.major_comp_rate,
  ms.median_survivor_los
FROM quartile_metrics qm
LEFT JOIN median_subsurvivor ms ON qm.quartile = ms.quartile

UNION ALL
SELECT
  'Overall_75_85_Female_90d' AS quartile_label,
  AVG(CASE WHEN dod IS NOT NULL AND DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 90 THEN 1 ELSE 0 END) AS mortality_90d_rate,
  NULL AS major_comp_rate,
  NULL AS median_survivor_los
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 75 AND 85;