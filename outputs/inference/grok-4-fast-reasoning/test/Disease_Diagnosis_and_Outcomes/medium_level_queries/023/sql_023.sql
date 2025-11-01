WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(TIMESTAMP(a.dischtime), TIMESTAMP(a.admittime), DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),
strokes AS (
  SELECT 
    hadm_id,
    MAX(CASE 
      WHEN icd_code LIKE '433%' OR icd_code LIKE '434%' OR icd_code LIKE '436%' OR icd_code LIKE 'I63%' 
      THEN 1 ELSE 0 
    END) AS has_ischemic,
    MAX(CASE 
      WHEN icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%' OR icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%' 
      THEN 1 ELSE 0 
    END) AS has_hemorrhagic
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_stroke AS (
  SELECT 
    c.*,
    s.has_ischemic,
    s.has_hemorrhagic
  FROM cohort c
  INNER JOIN strokes s
    ON c.hadm_id = s.hadm_id
  WHERE (s.has_ischemic = 1 AND s.has_hemorrhagic = 0) OR (s.has_hemorrhagic = 1 AND s.has_ischemic = 0)
),
comorb AS (
  SELECT 
    cs.subject_id,
    cs.hadm_id,
    cs.los,
    cs.hospital_expire_flag,
    cs.has_ischemic,
    cs.has_hemorrhagic,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%') 
        OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%')) 
      THEN 1 ELSE 0 
    END) AS has_diabetes,
    MAX(CASE 
      WHEN d.icd_code LIKE '585%' OR d.icd_code = '586' OR d.icd_code = 'V420' OR d.icd_code LIKE 'V451%' OR d.icd_code LIKE 'N18%' 
      THEN 1 ELSE 0 
    END) AS has_ckd,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '40[1-5]%') 
        OR (d.icd_version = 10 AND (d.icd_code = 'I10' OR d.icd_code LIKE 'I11%' OR d.icd_code LIKE 'I12%' OR d.icd_code LIKE 'I13%' OR d.icd_code LIKE 'I15%' OR d.icd_code LIKE 'I16%')) 
      THEN 1 ELSE 0 
    END) AS has_htn,
    MAX(CASE 
      WHEN d.icd_code LIKE '428%' OR d.icd_code LIKE 'I50%' 
      THEN 1 ELSE 0 
    END) AS has_chf,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND (d.icd_code LIKE '490%' OR d.icd_code LIKE '491%' OR d.icd_code LIKE '492%' OR d.icd_code LIKE '493%' OR d.icd_code LIKE '494%' OR d.icd_code LIKE '495%' OR d.icd_code LIKE '496%')) 
        OR (d.icd_version = 10 AND d.icd_code LIKE 'J4[0-7]%') 
      THEN 1 ELSE 0 
    END) AS has_copd,
    MAX(CASE 
      WHEN (d.icd_version = 9 AND (d.icd_code LIKE '14[0-9]%' OR d.icd_code LIKE '15[0-9]%' OR d.icd_code LIKE '16[0-9]%' OR d.icd_code LIKE '17[0-9]%' OR d.icd_code LIKE '18[0-9]%' OR d.icd_code LIKE '19[0-9]%' OR d.icd_code LIKE '20[0-8]%')) 
        OR (d.icd_version = 10 AND d.icd_code LIKE 'C%') 
      THEN 1 ELSE 0 
    END) AS has_cancer
  FROM cohort_stroke cs
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON cs.hadm_id = d.hadm_id
  GROUP BY 
    cs.subject_id, cs.hadm_id, cs.los, cs.hospital_expire_flag, 
    cs.has_ischemic, cs.has_hemorrhagic
),
scored AS (
  SELECT 
    *,
    CASE 
      WHEN has_hemorrhagic = 1 THEN 'hemorrhagic'
      ELSE 'ischemic'
    END AS stroke_type,
    (has_diabetes + has_ckd + has_htn + has_chf + has_copd + has_cancer) AS comorb_score
  FROM comorb
),
tertile AS (
  SELECT 
    *,
    NTILE(3) OVER (PARTITION BY stroke_type ORDER BY comorb_score) AS comorbidity_tertile
  FROM scored
)
SELECT 
  stroke_type,
  comorbidity_tertile,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los,
  ROUND(AVG(CASE WHEN los < 8 THEN 1.0 ELSE 0 END) * 100, 2) AS pct_los_lt8,
  ROUND(AVG(CASE WHEN los >= 8 THEN 1.0 ELSE 0 END) * 100, 2) AS pct_los_ge8,
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence,
  ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence
FROM tertile
GROUP BY stroke_type, comorbidity_tertile
ORDER BY stroke_type, comorbidity_tertile;