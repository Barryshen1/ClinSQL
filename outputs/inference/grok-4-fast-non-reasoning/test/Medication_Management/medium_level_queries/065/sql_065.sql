WITH cohort AS (
  -- Select male patients aged 77-87 with both diabetes and heart failure diagnoses
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admission_type != 'OBSERVATION'
    AND a.hadm_id IS NOT NULL
    -- Ensure both conditions present (distinct diagnoses)
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_diabetes
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd_diabetes 
        ON d_diabetes.icd_code = icd_diabetes.icd_code AND d_diabetes.icd_version = icd_diabetes.icd_version
      WHERE d_diabetes.hadm_id = a.hadm_id 
        AND (icd_diabetes.long_title LIKE '%diabetes mellitus%' OR d_diabetes.icd_code LIKE 'E[0-9][0-9]')
    )
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_hf
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd_hf 
        ON d_hf.icd_code = icd_hf.icd_code AND d_hf.icd_version = icd_hf.icd_version
      WHERE d_hf.hadm_id = a.hadm_id 
        AND (icd_hf.long_title LIKE '%heart failure%' OR d_hf.icd_code LIKE 'I50%')
    )
),

-- Prescriptions initiations
prescriptions_initiations AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    'prescription' AS source,
    CASE 
      WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(pr.drug) IN ('metformin', 'glipizide', 'glyburide', 'glimepiride', 'sitagliptin', 'linagliptin', 'saxagliptin', 'empagliflozin', 'canagliflozin', 'dapagliflozin') 
           OR LOWER(pr.drug) LIKE '%sulfonylurea%' OR LOWER(pr.drug) LIKE '%dpp-4%' OR LOWER(pr.drug) LIKE '%sglt2%' THEN 'oral'
    END AS med_type,
    pr.starttime AS event_time,
    pr.pharmacy_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON c.hadm_id = pr.hadm_id
  WHERE pr.drug IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND (LOWER(pr.drug) LIKE '%insulin%' 
         OR LOWER(pr.drug) IN ('metformin', 'glipizide', 'glyburide', 'glimepiride', 'sitagliptin', 'linagliptin', 'saxagliptin', 'empagliflozin', 'canagliflozin', 'dapagliflozin')
         OR LOWER(pr.drug) LIKE '%sulfonylurea%' OR LOWER(pr.drug) LIKE '%dpp-4%' OR LOWER(pr.drug) LIKE '%sglt2%')
),

-- ICU inputevents for insulin (IV/oral limited)
icu_initiations AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    'icu_input' AS source,
    CASE 
      WHEN LOWER(d_items.abbreviation) LIKE '%insulin%' OR LOWER(d_items.label) LIKE '%insulin%' THEN 'insulin'
      -- Oral agents rare in ICU inputs; skip or add if itemids known
    END AS med_type,
    ie.starttime AS event_time,
    ie.orderid AS pharmacy_id  -- Analogous to pharmacy_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON c.hadm_id = icu.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie ON icu.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d_items ON ie.itemid = d_items.itemid
  WHERE ie.statusdescription = 'Started'  -- Initiation proxy
    AND (LOWER(d_items.label) LIKE '%insulin%' OR LOWER(d_items.abbreviation) LIKE '%insulin%')  -- Specific itemids: 225798, etc., but keyword for simplicity
    AND ie.starttime IS NOT NULL
),

-- Combine all initiations
all_initiations AS (
  SELECT * FROM prescriptions_initiations
  UNION ALL
  SELECT * FROM icu_initiations
),

-- Window assignments (fixed self-reference with alias)
windowed_inits AS (
  SELECT 
    hadm_id,
    med_type,
    event_time AS aliased_event_time,
    -- 0-48h window
    CASE 
      WHEN event_time >= admittime AND event_time <= TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) THEN '0-48h'
      WHEN event_time >= TIMESTAMP_SUB(dischtime, INTERVAL 72 HOUR) AND event_time <= dischtime THEN 'final_72h'
      ELSE NULL
    END AS window
  FROM all_initiations
  WHERE med_type IS NOT NULL
    AND event_time IS NOT NULL
),

-- Aggregations per window
init_counts AS (
  SELECT 
    w.med_type,
    w.window,
    COUNT(DISTINCT w.hadm_id) AS num_admissions_with_init,
    COUNT(DISTINCT w.pharmacy_id) AS num_initiations
  FROM windowed_inits w
  INNER JOIN cohort c ON w.hadm_id = c.hadm_id
  WHERE w.window IS NOT NULL
    AND c.dischtime >= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)  -- Ensure viable windows (covers both 48h and 72h)
  GROUP BY med_type, window
),

-- Total admissions (all cohort eligible for both windows if LOS sufficient)
total_adms AS (
  SELECT 
    COUNT(hadm_id) AS total_adms
  FROM cohort c
  WHERE c.dischtime >= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
),

-- Precompute rates for net change calculation
init_rates AS (
  SELECT 
    ic.med_type,
    ic.window,
    ROUND(ic.num_initiations * 1.0 / ta.total_adms, 4) AS initiation_rate
  FROM init_counts ic
  CROSS JOIN total_adms ta
  WHERE ic.med_type IN ('insulin', 'oral')
)

-- Final rates and net change
SELECT 
  ir.med_type,
  ir.window,
  ir.initiation_rate,
  CASE 
    WHEN ir.window = 'final_72h' THEN 
      ROUND((
        (SELECT initiation_rate FROM init_rates WHERE med_type = ir.med_type AND window = 'final_72h') -
        (SELECT initiation_rate FROM init_rates WHERE med_type = ir.med_type AND window = '0-48h')
      ) * 100, 2)
    ELSE NULL 
  END AS net_change_pp
FROM init_rates ir
WHERE ir.med_type IN ('insulin', 'oral')
ORDER BY ir.med_type, ir.window;