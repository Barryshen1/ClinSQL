WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    i.intime,
    i.outtime,
    i.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    ON p.subject_id = d1.subject_id
    AND d1.icd_code LIKE 'E11%'
    AND d1.icd_version = 10
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON p.subject_id = d2.subject_id
    AND d2.icd_code LIKE 'I50%'
    AND d2.icd_version = 10
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.anchor_age BETWEEN 60 AND 70
    AND p.gender = 'F'
    AND i.los >= 2  -- Ensure at least 48 hours for meaningful windows
),
drug_classes AS (
  SELECT itemid, label,
    CASE
      WHEN LOWER(label) IN ('insulin', 'glucagon', 'metformin', 'glimepiride', 'glipizide', 'sitagliptin', 'empagliflozin', 'canagliflozin', 'dapagliflozin', 'pioglitazone', 'rosiglitazone', 'liraglutide', 'semaglutide', 'exenatide', 'repaglinide', 'nateglinide') THEN 'Antidiabetics'
      WHEN LOWER(label) IN ('metoprolol', 'carvedilol', 'propranolol', 'atenolol', 'bisoprolol', 'nadolol', 'labetalol', 'timolol') THEN 'Beta-blockers'
      WHEN LOWER(label) IN ('lisinopril', 'enalapril', 'ramipril', 'captopril', 'trandolapril', 'quinapril', 'benazepril', 'fosinopril', 'losartan', 'valsartan', 'irbesartan', 'candesartan', 'telmisartan', 'olmesartan', 'sacubitril/valsartan') THEN 'ACEi/ARB/ARNI'
      WHEN LOWER(label) IN ('furosemide', 'bumetanide', 'torsemide') THEN 'Loop diuretics'
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN (
    'insulin', 'glucagon', 'metformin', 'glimepiride', 'glipizide', 'sitagliptin', 'empagliflozin', 'canagliflozin', 'dapagliflozin', 'pioglitazone', 'rosiglitazone', 'liraglutide', 'semaglutide', 'exenatide', 'repaglinide', 'nateglinide',
    'metoprolol', 'carvedilol', 'propranolol', 'atenolol', 'bisoprolol', 'nadolol', 'labetalol', 'timolol',
    'lisinopril', 'enalapril', 'ramipril', 'captopril', 'trandolapril', 'quinapril', 'benazepril', 'fosinopril', 'losartan', 'valsartan', 'irbesartan', 'candesartan', 'telmisartan', 'olmesartan', 'sacubitril/valsartan',
    'furosemide', 'bumetanide', 'torsemide'
  )
),
initiations AS (
  SELECT
    c.subject_id,
    c.intime,
    c.outtime,
    dc.drug_class,
    ie.starttime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON c.subject_id = ie.subject_id AND c.intime <= ie.starttime AND ie.starttime <= c.outtime
  INNER JOIN drug_classes dc
    ON ie.itemid = dc.itemid
  WHERE ie.starttime IS NOT NULL
),
aggregated AS (
  SELECT
    drug_class,
    COUNT(DISTINCT CASE WHEN starttime BETWEEN intime AND intime + INTERVAL 48 HOUR THEN subject_id END) * 100.0 / COUNT(DISTINCT subject_id) AS init_pct_48h,
    COUNT(DISTINCT CASE WHEN starttime BETWEEN outtime - INTERVAL 24 HOUR AND outtime THEN subject_id END) * 100.0 / COUNT(DISTINCT subject_id) AS init_pct_final24h,
    (COUNT(DISTINCT CASE WHEN starttime BETWEEN outtime - INTERVAL 24 HOUR AND outtime THEN subject_id END) * 100.0 / COUNT(DISTINCT subject_id)) 
    - (COUNT(DISTINCT CASE WHEN starttime BETWEEN intime AND intime + INTERVAL 48 HOUR THEN subject_id END) * 100.0 / COUNT(DISTINCT subject_id)) AS abs_diff_pp
  FROM initiations
  GROUP BY drug_class
)
SELECT
  drug_class,
  ROUND(init_pct_48h, 2) AS init_pct_48h,
  ROUND(init_pct_final24h, 2) AS init_pct_final24h,
  ROUND(abs_diff_pp, 2) AS abs_diff_pp
FROM aggregated
ORDER BY drug_class;