WITH eligible_patients AS (
  -- Filter men aged 39-49
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 39 AND 49
),
chest_pain_admissions AS (
  -- Admissions with primary chest pain diagnosis (ICD-10 R07.*)
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN eligible_patients p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code
    AND d.icd_version = icd.icd_version
  WHERE d.seq_num = 1  -- Primary diagnosis
    AND d.icd_version = '10'  -- ICD-10
    AND d.icd_code LIKE 'R07%'  -- Chest pain codes
    AND icd.long_title LIKE '%chest pain%'  -- Ensure description match
),
hs_tnt_labs AS (
  -- All hs-TnT labs for eligible admissions
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN chest_pain_admissions cpa
    ON le.hadm_id = cpa.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE LOWER(li.label) LIKE '%troponin t%'  -- hs-TnT itemids (adjust if exact itemids known, e.g., 50910-50920)
    AND li.category = 'Chemistry'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND le.valueuom = 'ng/L'  -- Standard unit
),
initial_hs_tnt AS (
  -- Earliest hs-TnT per admission
  SELECT subject_id, hadm_id, valuenum,
         ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
  FROM hs_tnt_labs
),
categorized_tnt AS (
  -- Initial labs with categories
  SELECT hadm_id, valuenum,
         CASE
           WHEN valuenum <= 14 THEN 'Normal'
           WHEN valuenum <= 49 THEN 'Borderline'
           ELSE 'Myocardial injury'
         END AS category
  FROM initial_hs_tnt
  WHERE rn = 1
),
stats AS (
  SELECT
    category,
    COUNT(*) AS count,
    AVG(valuenum) AS mean_tnt,
    PERCENTILE_CONT(valuenum, 0.5) OVER (PARTITION BY category) AS median_tnt,
    PERCENTILE_CONT(valuenum, 0.25) OVER (PARTITION BY category) AS q1_tnt,
    PERCENTILE_CONT(valuenum, 0.75) OVER (PARTITION BY category) AS q3_tnt
  FROM categorized_tnt
  GROUP BY category
),
totals AS (
  SELECT COUNT(*) AS total_count
  FROM categorized_tnt
)
SELECT
  s.category,
  s.count,
  ROUND(s.count * 100.0 / t.total_count, 2) AS percentage,
  ROUND(s.mean_tnt, 2) AS mean_hs_tnt,
  ROUND(s.median_tnt, 2) AS median_hs_tnt,
  ROUND(s.q1_tnt, 2) AS iqr_q1,
  ROUND(s.q3_tnt, 2) AS iqr_q3
FROM stats s
CROSS JOIN totals t
ORDER BY
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial injury' THEN 3
  END;