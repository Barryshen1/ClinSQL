WITH cohort AS (
  -- Base cohort: females 78-88, post-cardiac arrest admissions
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    a.admission_type
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND d.seq_num = 1  -- principal diagnosis
    AND (d.icd_version = 'ICD-9' AND d.icd_code LIKE '427.5%' 
         OR d.icd_version = 'ICD-10' AND d.icd_code LIKE 'I46%')
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')  -- inpatient
),

meds AS (
  -- Aggregate medications in first 7 days: unique drugs, high-risk, routes
  SELECT 
    c.subject_id,
    c.hadm_id,
    -- Unique drugs (normalized)
    APPROX_COUNT_DISTINCT(
      COALESCE(
        LOWER(REGEXP_REPLACE(
          COALESCE(di.label, e.product_description, pr.drug), 
          r'(\s+(sulfate|hydrochloride|acetate|etc\.?))?', ''
        )), 
        'unknown'
      )
    ) AS unique_drugs,
    -- High-risk drugs (simplified list: count unique matching)
    APPROX_COUNT_DISTINCT(
      CASE 
        WHEN LOWER(COALESCE(di.label, e.product_description, pr.drug)) IN (
          'morphine', 'fentanyl', 'heparin', 'warfarin', 'dopamine', 'norepinephrine', 
          'amiodarone', 'digoxin', 'insulin', 'potassium chloride', 'lidocaine', 
          'epinephrine', 'nitroglycerin', 'vasopressin', 'dobutamine', 'milrinone',
          'propofol', 'methotrexate', 'cisplatin'  -- add more as needed
        ) THEN 
          LOWER(REGEXP_REPLACE(COALESCE(di.label, e.product_description, pr.drug), r'(\s+(sulfate|hydrochloride|acetate|etc\.?))?', ''))
        ELSE NULL
      END
    ) AS high_risk_drugs,
    -- Distinct routes
    APPROX_COUNT_DISTINCT(
      COALESCE(i.route, pr.route, e.route, 
               CASE WHEN di.category LIKE '%IV%' THEN 'IV' 
                    WHEN di.category LIKE '%oral%' THEN 'PO' ELSE 'UNKNOWN' END)
    ) AS routes
  FROM cohort c
  -- ICU inputevents (IV/NG meds)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` i 
    ON c.subject_id = i.subject_id 
    AND c.hadm_id = i.hadm_id
    AND i.starttime >= c.admittime 
    AND i.starttime < DATE_ADD(c.admittime, INTERVAL 7 DAY)
    AND i.amount IS NOT NULL
    AND i.amount > 0
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON i.itemid = di.itemid
  -- EMAR administrations
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` e 
    ON c.subject_id = e.subject_id 
    AND c.hadm_id = e.hadm_id  -- Added hadm_id join for accuracy
    AND e.charttime >= c.admittime 
    AND e.charttime < DATE_ADD(c.admittime, INTERVAL 7 DAY)
    AND e.dose_given IS NOT NULL 
    AND SAFE_CAST(e.dose_given AS FLOAT64) > 0
  -- Prescriptions (fallback for non-ICU/oral)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON c.subject_id = pr.subject_id 
    AND c.hadm_id = pr.hadm_id
    AND pr.starttime >= c.admittime 
    AND pr.starttime < DATE_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY c.subject_id, c.hadm_id
),

scores AS (
  -- Calculate score and assign tertiles
  SELECT 
    m.*,
    (COALESCE(unique_drugs, 0) + 2 * COALESCE(high_risk_drugs, 0) + COALESCE(routes, 0)) AS complexity_score,
    NTILE(3) OVER (ORDER BY (COALESCE(unique_drugs, 0) + 2 * COALESCE(high_risk_drugs, 0) + COALESCE(routes, 0))) AS tertile
  FROM meds m
),

readmissions AS (
  -- Flag 30-day readmits
  SELECT 
    s.subject_id,
    s.hadm_id,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p2 ON a2.subject_id = p2.subject_id
        WHERE a2.subject_id = s.subject_id 
          AND a2.hadm_id != s.hadm_id
          AND p2.anchor_age BETWEEN 78 AND 88  -- Ensure same age group
          AND a2.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
          AND a2.admittime > s.dischtime 
          AND a2.admittime <= DATE_ADD(s.dischtime, INTERVAL 30 DAY)
      ) THEN 1 ELSE 0 
    END AS has_readmit
  FROM scores s
)

-- Final metrics by tertile
SELECT 
  tertile,
  COUNT(DISTINCT hadm_id) AS count_admissions,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  AVG(EXTRACT(DAY FROM (dischtime - admittime))) AS mean_los_days,
  (SUM(CAST(hospital_expire_flag AS INT64)) * 100.0 / COUNT(DISTINCT hadm_id)) AS in_hospital_mortality_pct,
  (SUM(CAST(has_readmit AS INT64)) * 100.0 / COUNT(DISTINCT hadm_id)) AS readmission_30d_pct
FROM scores s
INNER JOIN cohort c ON s.subject_id = c.subject_id AND s.hadm_id = c.hadm_id
INNER JOIN readmissions r ON s.subject_id = r.subject_id AND s.hadm_id = r.hadm_id
GROUP BY tertile
ORDER BY tertile;