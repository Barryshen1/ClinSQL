WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    -- Check if the patient had any ICU stay
    CASE WHEN icu.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS had_icu
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiag
    ON diag.icd_code = ddiag.icd_code AND diag.icd_version = ddiag.icd_version
  LEFT JOIN (
    SELECT DISTINCT hadm_id 
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
    ON adm.hadm_id = icu.hadm_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 64 AND 74
    AND (ddiag.icd_code = 'G45.9' AND ddiag.icd_version = 10)
       OR (ddiag.icd_code = '435.9' AND ddiag.icd_version = 9)
    AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
  GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, icu.hadm_id
),
procedures AS (
  SELECT 
    p.hadm_id,
    p.chartdate,
    -- Calculate hospital day: day 1 is the day of admission
    DATE_DIFF(DATE(p.chartdate), DATE(c.admittime), DAY) + 1 AS hospital_day,
    -- Group into 1-3 and 4-7
    CASE 
      WHEN DATE_DIFF(DATE(p.chartdate), DATE(c.admittime), DAY) + 1 BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(DATE(p.chartdate), DATE(c.admittime), DAY) + 1 BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL 
    END AS day_group
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN cohort c
    ON p.hadm_id = c.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE 
    -- Filter for echocardiograms/ultrasounds
    (dp.icd_version = 10 AND dp.icd_code LIKE 'BH23%')
    OR (dp.icd_version = 9 AND dp.icd_code LIKE '88.72%')
    -- Ensure within the hospital stay days 1-7
    AND DATE_DIFF(DATE(p.chartdate), DATE(c.admittime), DAY) + 1 BETWEEN 1 AND 7
),
-- Count procedures per admission per day group
procedure_counts AS (
  SELECT 
    c.hadm_id,
    c.had_icu,
    COUNTIF(p.day_group = '1-3') AS count_1_3,
    COUNTIF(p.day_group = '4-7') AS count_4_7
  FROM cohort c
  LEFT JOIN procedures p
    ON c.hadm_id = p.hadm_id
  GROUP BY c.hadm_id, c.had_icu
)
-- Compute mean counts stratified by ICU use
SELECT 
  had_icu,
  AVG(count_1_3) AS mean_echo_1_3,
  AVG(count_4_7) AS mean_echo_4_7
FROM procedure_counts
GROUP BY had_icu
ORDER BY had_icu;