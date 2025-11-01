WITH hf_admissions AS (
  -- Step 1: Identify admissions with any heart failure diagnosis
  SELECT DISTINCT di.subject_id,
                  di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
),

cohort AS (
  -- Step 2: Define the HF cohort of 43–53 year-old males
  SELECT a.subject_id,
         a.hadm_id,
         p.anchor_age,
         a.admittime,
         a.dischtime,
         a.hospital_expire_flag,
         -- Compute hospital LOS in days
         DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM hf_admissions h
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON h.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
),

comorbidity_counts AS (
  -- Step 3: Count distinct non-HF ICD codes per admission
  SELECT c.subject_id,
         c.hadm_id,
         c.anchor_age,
         c.admittime,
         c.dischtime,
         c.los_days,
         c.hospital_expire_flag,
         COUNT(DISTINCT di.icd_code) AS comorbidity_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON c.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) NOT LIKE '%heart failure%'
    -- If there are diagnoses without a matching long_title, they still count as non-HF
    OR dd.long_title IS NULL
  GROUP BY c.subject_id,
           c.hadm_id,
           c.anchor_age,
           c.admittime,
           c.dischtime,
           c.los_days,
           c.hospital_expire_flag
),

quantiles AS (
  -- Step 4 & 5: Assign comorbidity tertiles and LOS quartiles
  SELECT *,
         NTILE(3) OVER (ORDER BY comorbidity_count) AS comorbidity_tertile,
         NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM comorbidity_counts
),

labeled AS (
  -- Map tertile numbers to labels
  SELECT subject_id,
         hadm_id,
         los_days,
         hospital_expire_flag,
         CASE comorbidity_tertile
           WHEN 1 THEN 'low'
           WHEN 2 THEN 'medium'
           WHEN 3 THEN 'high'
         END AS comorbidity_burden,
         los_quartile
  FROM quantiles
)

-- Step 6: Aggregate mortality by LOS quartile and comorbidity burden
SELECT
  los_quartile AS los_quartile,
  comorbidity_burden,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * AVG(hospital_expire_flag), 2) AS mortality_pct
FROM labeled
GROUP BY los_quartile, comorbidity_burden
ORDER BY los_quartile, 
         CASE comorbidity_burden
           WHEN 'low' THEN 1
           WHEN 'medium' THEN 2
           WHEN 'high' THEN 3
         END;