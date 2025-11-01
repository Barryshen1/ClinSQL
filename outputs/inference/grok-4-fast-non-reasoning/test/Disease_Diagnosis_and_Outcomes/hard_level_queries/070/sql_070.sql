WITH elixhauser_groups AS (
  -- Define Elixhauser ICD-10 groups and weights (simplified van Walraven weights; full list abbreviated for brevity)
  SELECT 
    subject_id,
    SUM(CASE 
      WHEN icd_code LIKE 'I09.%' OR icd_code LIKE 'I11.%' OR icd_code LIKE 'I13.%' OR icd_code LIKE 'I25.5%' OR icd_code LIKE 'I42%' OR icd_code LIKE 'I43%' OR icd_code LIKE 'I50%' THEN 3  -- CHF
      WHEN icd_code LIKE 'I26%' OR icd_code LIKE 'I27%' OR icd_code LIKE 'I28.0' OR icd_code LIKE 'I28.8%' OR icd_code LIKE 'I28.9' THEN -3  -- Pulm circ
      WHEN icd_code LIKE 'E66%' OR icd_code LIKE 'E78%' THEN -2  -- Obesity
      WHEN icd_code LIKE 'J40%' OR icd_code LIKE 'J41%' OR icd_code LIKE 'J42%' OR icd_code LIKE 'J43%' OR icd_code LIKE 'J44%' OR icd_code LIKE 'J47%' THEN 4  -- COPD
      WHEN icd_code LIKE 'D50%' OR icd_code LIKE 'D51%' OR icd_code LIKE 'D52%' OR icd_code LIKE 'D53%' THEN 6  -- Anemia
      WHEN icd_code LIKE 'I12%' OR icd_code LIKE 'I13%' OR icd_code LIKE 'N18%' OR icd_code LIKE 'N19%' OR icd_code LIKE 'N25.1' OR icd_code LIKE 'Z94.0' OR icd_code LIKE 'Z99.2' THEN 2  -- Renal
      WHEN icd_code LIKE 'F00%' OR icd_code LIKE 'F01%' OR icd_code LIKE 'F02%' OR icd_code LIKE 'F03%' THEN 0  -- Dementia (weight 0)
      -- Add more groups as needed (e.g., diabetes w/o CC 0, w/CC 2; hypo/hyper thyroid 0; etc.); full ~30 groups for accuracy
      ELSE 0 
    END) AS elix_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = '10'
  GROUP BY subject_id
),
base_cohort AS (
  SELECT DISTINCT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    COALESCE(e.elix_score, 0) AS comorbidity_score
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  LEFT JOIN elixhauser_groups e ON p.subject_id = e.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'I82.%'
),
percentile_75 AS (
  SELECT 
    PERCENTILE_CONT(comorbidity_score, 0.75) OVER() AS p75_score
  FROM base_cohort
),
high_comorb_cohort AS (
  SELECT 
    bc.*,
    p75.p75_score
  FROM base_cohort bc
  CROSS JOIN percentile_75 p75
  WHERE bc.comorbidity_score > p75.p75_score
),
complications AS (
  -- Major complications: ICD-based PE/bleed + AKI via labs
  SELECT 
    hc.subject_id,
    MAX(CASE 
      WHEN d_comp.icd_code LIKE 'I26%' OR d_comp.icd_code LIKE 'K92.2%' OR d_comp.icd_code LIKE 'I61%' THEN 1  -- PE, GI bleed, ICH
      WHEN le.max_creat >= 0.3 THEN 1  -- Simplified AKI (max creat rise; needs baseline logic in full query)
      ELSE 0 
    END) AS has_complication
  FROM high_comorb_cohort hc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_comp ON hc.subject_id = d_comp.subject_id 
    AND d_comp.hadm_id = hc.hadm_id
    AND PARSE_DATE('%Y-%m-%d', d_comp.chartdate) > PARSE_DATE('%Y-%m-%d', hc.admittime)
    AND d_comp.icd_version = '10'
  LEFT JOIN (
    SELECT 
      subject_id, 
      hadm_id, 
      MAX(valuenum) AS max_creat
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
    WHERE dli.label LIKE '%CREATININE%'
      AND valuenum IS NOT NULL
    GROUP BY subject_id, hadm_id
  ) le ON hc.subject_id = le.subject_id AND hc.hadm_id = le.hadm_id
  GROUP BY hc.subject_id
),
outcomes AS (
  SELECT 
    hc.subject_id,
    hc.admittime,
    p.dod,
    CASE WHEN p.dod IS NOT NULL 
         AND DATE(p.dod) <= DATE_ADD(DATE(hc.admittime), INTERVAL 30 DAY) THEN 1 ELSE 0 END AS day30_death,
    COALESCE(c.has_complication, 0) AS has_complication,
    CASE WHEN p.dod IS NOT NULL THEN DATE_DIFF(DATE(p.dod), DATE(hc.admittime), DAY) ELSE NULL END AS survival_days,
    hc.comorbidity_score,
    hc.anchor_age
  FROM high_comorb_cohort hc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON hc.subject_id = p.subject_id
  LEFT JOIN complications c ON hc.subject_id = c.subject_id
),
final_cohort AS (
  SELECT 
    *,
    -- Composite risk: elix + age adjustment + early DVT flag (simplified)
    comorbidity_score + (anchor_age - 64) * 0.5 AS composite_risk
  FROM outcomes
),
decedents_median AS (
  SELECT 
    APPROX_QUANTILES(survival_days, 2)[OFFSET(1)] AS median_survival_decedents_days
  FROM final_cohort
  WHERE survival_days IS NOT NULL
),
ntiled_cohort AS (
  SELECT *, NTILE(4) OVER (ORDER BY composite_risk) AS ntile
  FROM final_cohort
)
-- Aggregates
SELECT 
  COUNT(DISTINCT subject_id) AS cohort_size,
  SUM(day30_death) * 1.0 / COUNT(DISTINCT subject_id) AS day30_mortality_rate,
  SUM(has_complication) * 1.0 / COUNT(DISTINCT subject_id) AS major_complication_rate,
  dm.median_survival_decedents_days,
  -- Quartiles
  SUM(CASE WHEN ntile = 1 THEN 1 ELSE 0 END) AS q1_count,
  SUM(CASE WHEN ntile = 2 THEN 1 ELSE 0 END) AS q2_count,
  SUM(CASE WHEN ntile = 3 THEN 1 ELSE 0 END) AS q3_count,
  SUM(CASE WHEN ntile = 4 THEN 1 ELSE 0 END) AS q4_count
FROM ntilted_cohort nc
CROSS JOIN decedents_median dm
GROUP BY 1  -- Single row output
;