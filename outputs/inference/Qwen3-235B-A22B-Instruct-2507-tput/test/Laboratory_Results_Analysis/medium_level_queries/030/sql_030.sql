WITH ami_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I21', 'I22'))  -- AMI codes
  )
),
ami_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  INNER JOIN ami_codes ac
    ON di.icd_code = ac.icd_code AND di.icd_version = 10
),
patients_in_age_group AS (
  SELECT p.subject_id,
         EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN ami_admissions a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 64 AND 74
),
first_ami_admission AS (
  SELECT a.subject_id, a.hadm_id, a.admittime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM ami_admissions a
  INNER JOIN patients_in_age_group pag ON a.subject_id = pag.subject_id
),
index_troponin AS (
  SELECT fa.subject_id, fa.hadm_id, le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY fa.hadm_id ORDER BY le.charttime) AS rn
  FROM first_ami_admission fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON fa.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE dl.label = 'TROPONIN T HIGH SENSITIVE'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= fa.admittime
    AND fa.rn = 1  -- only first AMI admission per patient
),
categorized AS (
  SELECT 
    CASE
      WHEN valuenum <= 0.014 THEN 'Normal (≤0.014)'
      WHEN valuenum <= 0.052 THEN 'Borderline (0.015–0.052)'
      ELSE 'Myocardial Injury (>0.052)'
    END AS category
  FROM index_troponin
  WHERE rn = 1  -- first troponin in admission
)
SELECT 
  category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM categorized
GROUP BY category
ORDER BY 
  CASE category
    WHEN 'Normal (≤0.014)' THEN 1
    WHEN 'Borderline (0.015–0.052)' THEN 2
    WHEN 'Myocardial Injury (>0.052)' THEN 3
  END;