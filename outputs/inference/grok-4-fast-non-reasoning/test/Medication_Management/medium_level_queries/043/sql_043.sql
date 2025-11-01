WITH cohort AS (
  -- Define male inpatients aged 77-87 with diabetes AND heart failure
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR) AS first_48h_end,
    TIMESTAMP_SUB(a.dischtime, INTERVAL 12 HOUR) AS last_12h_start
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 77 AND 87
    AND p.gender = 'M'
    AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')  -- ELECTIVE, URGENT, EMERGENCY
    AND (a.dischtime - a.admittime) >= INTERVAL 12 HOUR  -- Valid last 12h
    AND EXISTS (
      -- Has diabetes (ICD-10)
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
      WHERE d1.subject_id = a.subject_id AND d1.hadm_id = a.hadm_id
        AND d1.icd_code LIKE 'E1[0-3]%' AND d1.icd_version = 'ICD-10-CM'
    )
    AND EXISTS (
      -- Has heart failure (ICD-10)
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.subject_id = a.subject_id AND d2.hadm_id = a.hadm_id
        AND d2.icd_code LIKE 'I50%' AND d2.icd_version = 'ICD-10-CM'
    )
    AND TIMESTAMP_SUB(a.dischtime, INTERVAL 12 HOUR) >= a.admittime  -- Ensure valid last_12h_start
),
total_cohort AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_patients
  FROM cohort
),
initiations AS (
  -- First initiation per drug category per admission
  SELECT 
    c.hadm_id,
    CASE 
      WHEN LOWER(TRIM(pr.drug)) LIKE '%insulin%' 
        OR LOWER(TRIM(pr.drug)) LIKE '%metformin%' 
        OR LOWER(TRIM(pr.drug)) LIKE '%glipizide%' 
        OR LOWER(TRIM(pr.drug)) LIKE '%glimepiri%'  -- Covers glimepiride, glyburide
        OR LOWER(TRIM(pr.drug)) LIKE '%sitagliptin%' THEN 'Antidiabetics'
      WHEN LOWER(TRIM(pr.drug)) LIKE '%metoprolol%' 
        OR LOWER(TRIM(pr.drug)) LIKE '%atenolol%' 
        OR LOWER(TRIM(pr.drug)) LIKE '%carvedilol%' 
        OR LOWER(TRIM(pr.drug)) LIKE '%bisoprolol%' THEN 'Beta-blockers'
      WHEN LOWER(TRIM(pr.drug)) LIKE '%lisinopril%' 
        OR LOWER(TRIM(pr.drug)) LIKE '%losartan%' 
        OR LOWER(TRIM(pr.drug)) LIKE '%valsartan%' 
        OR LOWER(TRIM(pr.drug)) LIKE '%sacubitril%' 
        OR LOWER(TRIM(pr.drug)) LIKE '%enalapril%' THEN 'ACEi/ARB/ARNI'
      WHEN LOWER(TRIM(pr.drug)) LIKE '%furosemide%' 
        OR LOWER(TRIM(pr.drug)) LIKE '%bumetanide%' 
        OR LOWER(TRIM(pr.drug)) LIKE '%torsemide%' THEN 'Loop diuretics'
    END AS drug_category,
    MIN(pr.starttime) AS first_starttime  -- Earliest start for initiation check
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.drug_type = 'MAIN'
    AND pr.starttime IS NOT NULL
    AND pr.starttime >= TIMESTAMP_ADD(c.admittime, INTERVAL 1 HOUR)  -- Exclude likely home meds (start >1h after admit)
    AND (
      LOWER(TRIM(pr.drug)) LIKE '%insulin%' OR LOWER(TRIM(pr.drug)) LIKE '%metformin%' OR LOWER(TRIM(pr.drug)) LIKE '%glipizide%' OR LOWER(TRIM(pr.drug)) LIKE '%glimepiri%' OR LOWER(TRIM(pr.drug)) LIKE '%sitagliptin%' OR
      LOWER(TRIM(pr.drug)) LIKE '%metoprolol%' OR LOWER(TRIM(pr.drug)) LIKE '%atenolol%' OR LOWER(TRIM(pr.drug)) LIKE '%carvedilol%' OR LOWER(TRIM(pr.drug)) LIKE '%bisoprolol%' OR
      LOWER(TRIM(pr.drug)) LIKE '%lisinopril%' OR LOWER(TRIM(pr.drug)) LIKE '%losartan%' OR LOWER(TRIM(pr.drug)) LIKE '%valsartan%' OR LOWER(TRIM(pr.drug)) LIKE '%sacubitril%' OR LOWER(TRIM(pr.drug)) LIKE '%enalapril%' OR
      LOWER(TRIM(pr.drug)) LIKE '%furosemide%' OR LOWER(TRIM(pr.drug)) LIKE '%bumetanide%' OR LOWER(TRIM(pr.drug)) LIKE '%torsemide%'
    )
  GROUP BY c.hadm_id, drug_category
  HAVING first_starttime IS NOT NULL AND drug_category IS NOT NULL
),
window_initiations AS (
  -- Classify initiations into windows
  SELECT 
    i.drug_category,
    SUM(CASE WHEN i.first_starttime <= c.first_48h_end THEN 1 ELSE 0 END) AS first_48h_inits,
    SUM(CASE WHEN i.first_starttime >= c.last_12h_start THEN 1 ELSE 0 END) AS last_12h_inits
  FROM initiations i
  INNER JOIN cohort c ON i.hadm_id = c.hadm_id
  GROUP BY i.drug_category
)
-- Compute rates and net change
SELECT 
  wi.drug_category,
  (wi.first_48h_inits * 100.0 / tc.total_patients) AS first_48h_rate_pct,
  (wi.last_12h_inits * 100.0 / tc.total_patients) AS last_12h_rate_pct,
  ((wi.last_12h_inits - wi.first_48h_inits) * 100.0 / tc.total_patients) AS net_change_pct,
  tc.total_patients
FROM window_initiations wi
CROSS JOIN total_cohort tc
ORDER BY 
  CASE wi.drug_category
    WHEN 'Antidiabetics' THEN 1
    WHEN 'Beta-blockers' THEN 2
    WHEN 'ACEi/ARB/ARNI' THEN 3
    WHEN 'Loop diuretics' THEN 4
  END;