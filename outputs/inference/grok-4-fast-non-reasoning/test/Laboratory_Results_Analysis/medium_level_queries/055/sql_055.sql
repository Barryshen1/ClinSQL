WITH eligible_admissions AS (
  -- Filter patients and primary diagnoses for chest pain or AMI
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND CAST(d.seq_num AS STRING) = '1'
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND a.hospital_expire_flag = 0
    AND d.icd_version = '10'
    AND (LOWER(d.icd_code) LIKE 'r07.%'  -- Chest pain
         OR LOWER(d.icd_code) LIKE 'i21.%'  -- AMI initial
         OR LOWER(d.icd_code) LIKE 'i22.%')  -- AMI subsequent
),
eligible_with_tnt AS (
  -- Filter to admissions with at least one hs-TnT in first 24h
  SELECT ea.*
  FROM eligible_admissions ea
  WHERE EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    WHERE le.subject_id = ea.subject_id
      AND le.hadm_id = ea.hadm_id
      AND le.itemid IN (50922, 50923, 50924, 50925)  -- hs-TnT itemids
      AND le.charttime >= ea.admittime
      AND le.charttime <= TIMESTAMP_ADD(ea.admittime, INTERVAL 1 DAY)
      AND le.valuenum IS NOT NULL
  )
),
index_hstnt AS (
  -- Get first hs-TnT within 24 hours of admission
  SELECT 
    ew.*,
    FIRST_VALUE(le.valuenum IGNORE NULLS) OVER (
      PARTITION BY ew.hadm_id 
      ORDER BY le.charttime ASC
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS index_hstnt
  FROM eligible_with_tnt ew
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ew.subject_id = le.subject_id
    AND ew.hadm_id = le.hadm_id
    AND le.itemid IN (50922, 50923, 50924, 50925)
    AND le.charttime >= ew.admittime
    AND le.charttime <= TIMESTAMP_ADD(ew.admittime, INTERVAL 1 DAY)
)
SELECT 
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percentage,
  ROUND(AVG(los), 1) AS mean_los_days
FROM (
  SELECT 
    *,
    CASE 
      WHEN index_hstnt < 14 THEN 'Normal'
      WHEN index_hstnt < 50 THEN 'Borderline'
      ELSE 'Myocardial Injury'
    END AS category
  FROM index_hstnt
  QUALIFY index_hstnt IS NOT NULL
)
GROUP BY category
ORDER BY 
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
  END
;
-- Overall mean LOS (add if needed): SELECT ROUND(AVG(los), 1) AS overall_mean_los FROM index_hstnt WHERE index_hstnt IS NOT NULL;