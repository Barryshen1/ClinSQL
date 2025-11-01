WITH upper_gi_bleeding_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    -- ICD-10
    (icd_version = 10 AND (
      (icd_code BETWEEN 'K250' AND 'K256') OR
      (icd_code BETWEEN 'K260' AND 'K266') OR
      (icd_code BETWEEN 'K270' AND 'K276') OR
      (icd_code BETWEEN 'K280' AND 'K286') OR
      icd_code IN ('K920', 'K921', 'K922')
    ))
    OR
    -- ICD-9
    (icd_version = 9 AND (
      (icd_code BETWEEN '5310' AND '5316') OR
      (icd_code BETWEEN '5320' AND '5326') OR
      (icd_code BETWEEN '5330' AND '5336') OR
      (icd_code BETWEEN '5340' AND '5346') OR
      icd_code IN ('5780', '5781', '5789')
    ))
),
egd_procedure_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    LOWER(long_title) LIKE '%endoscopy%'
    AND (LOWER(long_title) LIKE '%upper%' 
         OR LOWER(long_title) LIKE '%esophag%' 
         OR LOWER(long_title) LIKE '%gastroduoden%')
),
filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Calculate length of stay in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- Join with diagnoses to filter for upper GI bleeding
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN upper_gi_bleeding_codes u
    ON d.icd_code = u.icd_code AND d.icd_version = u.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 53 AND 63
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) BETWEEN 1 AND 8
),
admission_procedure_counts AS (
  SELECT
    fa.hadm_id,
    fa.los_days,
    COUNT(p.icd_code) AS procedure_count
  FROM filtered_admissions fa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON fa.hadm_id = p.hadm_id
    AND EXISTS (
      SELECT 1 
      FROM egd_procedure_codes e 
      WHERE p.icd_code = e.icd_code AND p.icd_version = e.icd_version
    )
    -- Ensure procedure happened during admission
    AND DATE(p.chartdate) BETWEEN DATE(fa.admittime) AND DATE(fa.dischtime)
  GROUP BY fa.hadm_id, fa.los_days
)
SELECT
  CASE 
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
  END AS los_group,
  APPROX_QUANTILES(procedure_count, 1000)[OFFSET(250)] AS p25,
  APPROX_QUANTILES(procedure_count, 1000)[OFFSET(500)] AS p50,
  APPROX_QUANTILES(procedure_count, 1000)[OFFSET(750)] AS p75
FROM admission_procedure_counts
GROUP BY los_group;