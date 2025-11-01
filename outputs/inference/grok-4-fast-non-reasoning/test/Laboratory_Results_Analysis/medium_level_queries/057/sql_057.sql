WITH acs_admissions AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND d.seq_num = 1
    AND d.icd_version = '10'
    AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%')
    AND (icd.long_title LIKE '%angina%' OR icd.long_title LIKE '%myocardial%')
),
index_troponin AS (
  SELECT 
    hadm_id,
    TIMESTAMP(MIN(charttime)) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE REGEXP_CONTAINS(LOWER(li.label), r'troponin.*t')
    AND li.category = 'Chemistry'
    AND le.valueuom = 'ng/mL'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
  GROUP BY hadm_id
),
first_troponin_values AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    le.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  INNER JOIN index_troponin it
    ON le.hadm_id = it.hadm_id
    AND le.charttime = it.first_charttime
  WHERE REGEXP_CONTAINS(LOWER(li.label), r'troponin.*t')
    AND li.category = 'Chemistry'
    AND le.valueuom = 'ng/mL'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
)
SELECT 
  CASE 
    WHEN valuenum <= 0.04 THEN 'normal (≤0.04)'
    WHEN valuenum > 0.04 AND valuenum <= 0.1 THEN 'borderline (>0.04–0.1)'
    ELSE 'elevated (>0.1)'
  END AS troponin_category,
  COUNT(DISTINCT f.hadm_id) AS admission_count
FROM acs_admissions aa
INNER JOIN first_troponin_values f
  ON aa.hadm_id = f.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON aa.hadm_id = a.hadm_id
WHERE f.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
GROUP BY troponin_category
ORDER BY 
  CASE troponin_category
    WHEN 'normal (≤0.04)' THEN 1
    WHEN 'borderline (>0.04–0.1)' THEN 2
    ELSE 3
  END;