WITH stroke_cohort AS (
  -- Base cohort: females 48-58 with principal hemorrhagic stroke
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND d.icd_version = '10'
    AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%')
    AND d.seq_num = 1
),
lab_critical AS (
  -- Flag critical labs per event in first 72h
  SELECT 
    sc.hadm_id,
    sc.admittime,
    l.itemid,
    l.valuenum,
    l.valueuom,
    CASE
      WHEN l.itemid = INT64(50868) AND (l.valuenum < 130 OR l.valuenum > 150) THEN 1  -- Na
      WHEN l.itemid = INT64(50971) AND (l.valuenum < 2.5 OR l.valuenum > 6.0) THEN 1  -- K
      WHEN l.itemid = INT64(50983) AND (l.valuenum < 90 OR l.valuenum > 110) THEN 1  -- Cl
      WHEN l.itemid = INT64(51006) AND l.valuenum > 50 THEN 1  -- BUN
      WHEN l.itemid = INT64(50912) AND l.valuenum > 3.0 THEN 1  -- Creat
      WHEN l.itemid = INT64(51222) AND (l.valuenum < 3.3 OR l.valuenum > 30) THEN 1  -- WBC
      WHEN l.itemid = INT64(51279) AND (l.valuenum < 6.5 OR l.valuenum > 20) THEN 1  -- Hgb
      WHEN l.itemid = INT64(51265) AND (l.valuenum < 100 OR l.valuenum > 800) THEN 1  -- Plt
      WHEN l.itemid = INT64(51275) AND l.valuenum > 60 THEN 1  -- PTT
      WHEN l.itemid = INT64(51237) AND l.valuenum > 1.5 THEN 1  -- INR
      WHEN l.itemid = INT64(51274) AND l.valuenum > 18 THEN 1  -- PT
      WHEN l.itemid = INT64(50878) AND l.valuenum > 200 THEN 1  -- ALT
      WHEN l.itemid = INT64(50885) AND l.valuenum > 200 THEN 1  -- AST
      WHEN l.itemid = INT64(50862) AND l.valuenum > 2.0 THEN 1  -- Bili
      WHEN l.itemid = INT64(50813) AND l.valuenum > 4.0 THEN 1  -- Lactate
      WHEN l.itemid = INT64(50827) AND l.valuenum > 0.4 THEN 1  -- Trop
      WHEN l.itemid = INT64(50122) AND (l.valuenum < 7.2 OR l.valuenum > 7.55) THEN 1  -- pH
      WHEN l.itemid = INT64(50121) AND (l.valuenum < 35 OR l.valuenum > 45) THEN 1  -- pCO2
      WHEN l.itemid = INT64(50131) AND (l.valuenum < 22 OR l.valuenum > 26) THEN 1  -- HCO3
      ELSE 0
    END AS critical_flag,
    CASE
      -- Severe examples (multiplier 2)
      WHEN l.itemid = INT64(50868) AND (l.valuenum < 120 OR l.valuenum > 160) THEN 2
      WHEN l.itemid = INT64(50971) AND (l.valuenum < 2.8 OR l.valuenum > 7.0) THEN 2
      WHEN l.itemid = INT64(51265) AND l.valuenum < 50 THEN 2  -- Severe thrombocytopenia
      WHEN l.itemid = INT64(50122) AND l.valuenum < 7.1 THEN 2  -- Severe acidosis
      ELSE 1
    END AS severity
  FROM stroke_cohort sc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON sc.subject_id = l.subject_id AND sc.hadm_id = l.hadm_id
  WHERE l.charttime >= sc.admittime
    AND l.charttime <= DATETIME_ADD(sc.admittime, INTERVAL 3 DAY)
    AND l.valuenum IS NOT NULL
    AND l.itemid IN (
      INT64(50868), INT64(50971), INT64(50983), INT64(51006), INT64(50912), INT64(51222), INT64(51279), INT64(51265), 
      INT64(51275), INT64(51237), INT64(51274), INT64(50878), INT64(50885), INT64(50862), INT64(50813), INT64(50827), 
      INT64(50122), INT64(50121), INT64(50131)
    )
    -- Simplified unit filter (focus on common units; adjust if needed)
    AND (
      (l.itemid IN (INT64(50868), INT64(50971), INT64(50983)) AND l.valueuom IN ('mEq/L', 'mmol/L')) OR
      (l.itemid IN (INT64(51006), INT64(50912)) AND l.valueuom = 'mg/dL') OR
      (l.itemid = INT64(51222) AND l.valueuom LIKE '%/uL%') OR
      (l.itemid = INT64(51279) AND l.valueuom = 'g/dL') OR
      (l.itemid = INT64(51265) AND l.valueuom LIKE '%/uL%') OR
      (l.itemid IN (INT64(51275), INT64(51274)) AND l.valueuom = 'sec') OR
      (l.itemid = INT64(51237) AND l.valueuom IS NULL) OR  -- INR unitless
      (l.itemid IN (INT64(50878), INT64(50885)) AND l.valueuom = 'IU/L') OR
      (l.itemid = INT64(50862) AND l.valueuom = 'mg/dL') OR
      (l.itemid = INT64(50813) AND l.valueuom = 'mmol/L') OR
      (l.itemid = INT64(50827) AND l.valueuom = 'ng/mL') OR
      (l.itemid IN (INT64(50122), INT64(50121), INT64(50131)) AND l.valueuom IN ('', 'mmHg', 'mEq/L', 'mmol/L'))
    )
),
lab_scores AS (
  -- Aggregate scores per hadm_id
  SELECT 
    hadm_id,
    admittime,
    SUM(critical_flag * severity) AS labinstability_score,
    COUNTIF(critical_flag = 1) AS num_critical_labs
  FROM lab_critical
  GROUP BY hadm_id, admittime
),
p90_threshold AS (
  SELECT 
    PERCENTILE_CONT(0.9, labinstability_score) OVER() AS p90_score
  FROM lab_scores
)
SELECT 
  'High-risk (>=P90)' AS group_type,
  COUNT(DISTINCT ls.hadm_id) AS num_patients,
  AVG(ls.labinstability_score) AS mean_labinstability_score,
  pt.p90_score AS p90_threshold,
  AVG(ls.num_critical_labs) AS avg_critical_labs_per_patient,
  AVG(sc.hospital_expire_flag * 100) AS mortality_pct,
  AVG(DATE_DIFF(COALESCE(sc.dischtime, sc.deathtime), sc.admittime, DAY)) AS mean_los_days
FROM lab_scores ls
CROSS JOIN p90_threshold pt
INNER JOIN stroke_cohort sc ON ls.hadm_id = sc.hadm_id
WHERE ls.labinstability_score >= pt.p90_score

UNION ALL

SELECT 
  'Age-matched cohort (<P90)' AS group_type,
  COUNT(DISTINCT ls.hadm_id) AS num_patients,
  AVG(ls.labinstability_score) AS mean_labinstability_score,
  pt.p90_score AS p90_threshold,
  AVG(ls.num_critical_labs) AS avg_critical_labs_per_patient,
  AVG(sc.hospital_expire_flag * 100) AS mortality_pct,
  AVG(DATE_DIFF(COALESCE(sc.dischtime, sc.deathtime), sc.admittime, DAY)) AS mean_los_days
FROM lab_scores ls
CROSS JOIN p90_threshold pt
INNER JOIN stroke_cohort sc ON ls.hadm_id = sc.hadm_id
WHERE ls.labinstability_score < pt.p90_score
ORDER BY group_type;