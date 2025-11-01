WITH eligible_patients AS (
  -- Base cohort: males aged 87-97 with primary ACS admission
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    AND LOWER(icd.long_title) LIKE '%acute myocardial infarction%'
),
troponin_itemids AS (
  -- Identify Troponin T itemids
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE category = 'Chemistry'
    AND LOWER(label) LIKE '%troponin t%'
),
index_troponin AS (
  -- First Troponin T lab within 24h of admission
  SELECT 
    ep.subject_id,
    ep.hadm_id,
    ep.admittime,
    ep.hospital_expire_flag,
    le.charttime,
    le.valuenum,
    CASE 
      WHEN le.valuenum <= 0.1 THEN 'Normal/Minimal'
      WHEN le.valuenum > 0.1 AND le.valuenum <= 0.5 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM eligible_patients ep
  INNER JOIN troponin_itemids ti
    ON 1=1  -- Placeholder; actual join via labevents
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ep.hadm_id = le.hadm_id
    AND ti.itemid = le.itemid
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND le.charttime >= ep.admittime
    AND EXTRACT(DAY FROM (le.charttime - ep.admittime)) <= 1
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ep.hadm_id ORDER BY le.charttime ASC) = 1
)
-- Aggregations by category
SELECT 
  troponin_category,
  COUNT(*) AS patient_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_rate_pct
FROM index_troponin
GROUP BY troponin_category
ORDER BY 
  CASE troponin_category
    WHEN 'Normal/Minimal' THEN 1
    WHEN 'Borderline' THEN 2
    ELSE 3
  END;