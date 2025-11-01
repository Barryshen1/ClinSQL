WITH cohort AS (
  -- Define cohort: males 63-73 at admission with primary T2DM (E11) and any HF (I50)
  SELECT DISTINCT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    -- Derived DOB for age calculation (MIMIC-IV anonymization)
    DATE(p.anchor_year, 1, 1) - INTERVAL EXTRACT(DOY FROM DATE(p.anchor_year, 1, 1)) DAY + INTERVAL p.anchor_age YEAR AS dob
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
    AND EXTRACT(YEAR FROM a.admittime) = p.anchor_year  -- Single-year admissions
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE p.gender = 'M'
    AND TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year, 1, 1) - INTERVAL EXTRACT(DOY FROM DATE(p.anchor_year, 1, 1)) DAY + INTERVAL p.anchor_age YEAR, YEAR) BETWEEN 63 AND 73
    AND d.icd_code LIKE 'E11%'  -- Primary T2DM (code directly)
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.hadm_id = a.hadm_id AND d2.icd_code LIKE 'I50%'  -- HF anywhere
    )
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY')
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 24  -- LOS >=24h
),

prescriptions_timed AS (
  -- All relevant prescriptions for cohort with time windows
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    pr.starttime,
    CASE 
      WHEN pr.starttime >= c.admittime 
       AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY )  -- Added space after DAY
      THEN 'first_24h'
      WHEN pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 1 DAY)
       AND pr.starttime < c.dischtime
      THEN 'final_24h'
    END AS window,
    CASE 
      WHEN LOWER(TRIM(pr.drug)) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(TRIM(pr.drug)) LIKE '%metformin%' 
        OR LOWER(TRIM(pr.drug)) LIKE '%glipizide%' OR LOWER(TRIM(pr.drug)) LIKE '%glyburide%'
        OR LOWER(TRIM(pr.drug)) LIKE '%glimepiride%' OR LOWER(TRIM(pr.drug)) LIKE '%sitagliptin%'
        OR LOWER(TRIM(pr.drug)) LIKE '%pioglitazone%' OR LOWER(TRIM(pr.drug)) LIKE '%repaglinide%'
        OR LOWER(TRIM(pr.drug)) LIKE '%dulaglutide%' OR LOWER(TRIM(pr.drug)) LIKE '%empagliflozin%'
        OR LOWER(TRIM(pr.drug)) LIKE '%linagliptin%' OR LOWER(TRIM(pr.drug)) LIKE '%canagliflozin%'
        OR LOWER(TRIM(pr.drug)) LIKE '%acarbose%' OR LOWER(TRIM(pr.drug)) LIKE '%saxagliptin%'
        OR LOWER(TRIM(pr.drug)) LIKE '%januvia%' OR LOWER(TRIM(pr.drug)) LIKE '% Jardiance%'
      THEN 'oral_agents'
    END AS drug_category
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime BETWEEN c.admittime AND c.dischtime  -- In-admission orders only
    AND (LOWER(TRIM(pr.drug)) LIKE '%insulin%' 
         OR LOWER(TRIM(pr.drug)) LIKE '%metformin%' 
         OR LOWER(TRIM(pr.drug)) LIKE '%glipizide%' OR LOWER(TRIM(pr.drug)) LIKE '%glyburide%'
         OR LOWER(TRIM(pr.drug)) LIKE '%glimepiride%' OR LOWER(TRIM(pr.drug)) LIKE '%sitagliptin%'
         OR LOWER(TRIM(pr.drug)) LIKE '%pioglitazone%' OR LOWER(TRIM(pr.drug)) LIKE '%repaglinide%'
         OR LOWER(TRIM(pr.drug)) LIKE '%dulaglutide%' OR LOWER(TRIM(pr.drug)) LIKE '%empagliflozin%'
         OR LOWER(TRIM(pr.drug)) LIKE '%linagliptin%' OR LOWER(TRIM(pr.drug)) LIKE '%canagliflozin%'
         OR LOWER(TRIM(pr.drug)) LIKE '%acarbose%' OR LOWER(TRIM(pr.drug)) LIKE '%saxagliptin%'
         OR LOWER(TRIM(pr.drug)) LIKE '%januvia%' OR LOWER(TRIM(pr.drug)) LIKE '% Jardiance%')
),

window_refs AS (
  -- Generate all hadm_id x window combinations for denominator
  SELECT hadm_id, 'first_24h' AS window
  FROM cohort
  UNION ALL
  SELECT hadm_id, 'final_24h' AS window
  FROM cohort
),

prevalence_raw AS (
  -- Join to compute numerator (with drug) and denominator (total)
  SELECT 
    wr.window,
    wr.hadm_id,
    MAX(pt.drug_category) AS drug_category  -- MAX to handle potential multiples per window/hadm
  FROM window_refs wr
  LEFT JOIN prescriptions_timed pt
    ON wr.hadm_id = pt.hadm_id AND wr.window = pt.window
  GROUP BY wr.window, wr.hadm_id
),

prevalence AS (
  SELECT 
    COALESCE(drug_category, 'none') AS drug_category,
    window,
    COUNT(DISTINCT CASE WHEN drug_category IN ('insulin', 'oral_agents') THEN hadm_id END) AS num_with_drug,
    COUNT(DISTINCT hadm_id) AS total_admissions
  FROM prevalence_raw
  GROUP BY drug_category, window
)

-- Final output: prevalence % and net change (pp)
SELECT 
  CASE 
    WHEN drug_category = 'insulin' THEN 'Insulin'
    WHEN drug_category = 'oral_agents' THEN 'Oral Agents'
  END AS drug_category,
  ROUND((SUM(CASE WHEN window = 'first_24h' THEN num_with_drug END) * 100.0 / SUM(CASE WHEN window = 'first_24h' THEN total_admissions END)), 2) AS first_24h_prevalence_pct,
  ROUND((SUM(CASE WHEN window = 'final_24h' THEN num_with_drug END) * 100.0 / SUM(CASE WHEN window = 'final_24h' THEN total_admissions END)), 2) AS final_24h_prevalence_pct,
  ROUND(
    (SUM(CASE WHEN window = 'final_24h' THEN num_with_drug END) * 100.0 / SUM(CASE WHEN window = 'final_24h' THEN total_admissions END)) -
    (SUM(CASE WHEN window = 'first_24h' THEN num_with_drug END) * 100.0 / SUM(CASE WHEN window = 'first_24h' THEN total_admissions END)), 
    2
  ) AS net_change_pp
FROM prevalence
WHERE drug_category IN ('insulin', 'oral_agents')
GROUP BY drug_category
ORDER BY drug_category;