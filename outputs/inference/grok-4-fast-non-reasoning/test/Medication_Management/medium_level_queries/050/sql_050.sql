WITH t2dm_adms AS (
  -- Admissions with T2DM
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON CAST(a.hadm_id AS STRING) = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE')
    AND (
      (d.icd_version = '10' AND d.icd_code LIKE 'E11%') OR
      (d.icd_version = '9' AND d.icd_code LIKE '250.4%')
    )
),

hf_adms AS (
  -- Admissions with heart failure
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON CAST(a.hadm_id AS STRING) = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE')
    AND (
      (d.icd_version = '10' AND d.icd_code LIKE 'I50%') OR
      (d.icd_version = '9' AND d.icd_code LIKE '428%')
    )
),

cohort AS (
  -- Intersect for admissions with both T2DM and HF
  SELECT t2dm.subject_id, t2dm.hadm_id, t2dm.admittime, t2dm.dischtime
  FROM t2dm_adms t2dm
  INNER JOIN hf_adms hf ON t2dm.hadm_id = hf.hadm_id
),

med_events AS (
  -- Prescriptions: Antidiabetic
  SELECT 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime,
    p.starttime, p.stoptime,
    'Antidiabetic' AS drug_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.subject_id = p.subject_id AND CAST(c.hadm_id AS STRING) = p.hadm_id
  WHERE LOWER(TRIM(p.drug)) LIKE '%insulin%' 
     OR LOWER(TRIM(p.drug)) LIKE '%metformin%' 
     OR LOWER(TRIM(p.drug)) LIKE '%glipizide%' 
     OR LOWER(TRIM(p.drug)) LIKE '%glyburide%'
     OR LOWER(TRIM(p.drug)) LIKE '%glimepiride%'

  UNION ALL

  -- ICU inputs: Antidiabetic
  SELECT 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime,
    i.starttime, i.endtime AS stoptime,
    'Antidiabetic' AS drug_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` i
    ON c.subject_id = i.subject_id AND CAST(c.hadm_id AS STRING) = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON i.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%insulin%' 
     OR i.itemid IN (225798, 225799)  -- Common insulin itemids

  UNION ALL

  -- Prescriptions: Beta-Blocker
  SELECT 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime,
    p.starttime, p.stoptime,
    'Beta-Blocker' AS drug_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.subject_id = p.subject_id AND CAST(c.hadm_id AS STRING) = p.hadm_id
  WHERE LOWER(TRIM(p.drug)) LIKE '%metoprolol%' 
     OR LOWER(TRIM(p.drug)) LIKE '%atenolol%' 
     OR LOWER(TRIM(p.drug)) LIKE '%carvedilol%' 
     OR LOWER(TRIM(p.drug)) LIKE '%bisoprolol%'

  UNION ALL

  -- ICU inputs: Beta-Blocker
  SELECT 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime,
    i.starttime, i.endtime AS stoptime,
    'Beta-Blocker' AS drug_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` i
    ON c.subject_id = i.subject_id AND CAST(c.hadm_id AS STRING) = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON i.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%metoprolol%' 
     OR LOWER(di.label) LIKE '%esmolol%'

  UNION ALL

  -- Prescriptions: ACEi/ARB/ARNI
  SELECT 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime,
    p.starttime, p.stoptime,
    'ACEi/ARB/ARNI' AS drug_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.subject_id = p.subject_id AND CAST(c.hadm_id AS STRING) = p.hadm_id
  WHERE LOWER(TRIM(p.drug)) LIKE '%lisinopril%' 
     OR LOWER(TRIM(p.drug)) LIKE '%losartan%' 
     OR LOWER(TRIM(p.drug)) LIKE '%valsartan%' 
     OR LOWER(TRIM(p.drug)) LIKE '%sacubitril%'
     OR LOWER(TRIM(p.drug)) LIKE '%captopril%'

  UNION ALL

  -- ICU inputs: ACEi/ARB/ARNI
  SELECT 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime,
    i.starttime, i.endtime AS stoptime,
    'ACEi/ARB/ARNI' AS drug_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` i
    ON c.subject_id = i.subject_id AND CAST(c.hadm_id AS STRING) = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON i.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%lisinopril%' 
     OR LOWER(di.label) LIKE '%enalapril%'

  UNION ALL

  -- Prescriptions: Loop Diuretic
  SELECT 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime,
    p.starttime, p.stoptime,
    'Loop Diuretic' AS drug_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.subject_id = p.subject_id AND CAST(c.hadm_id AS STRING) = p.hadm_id
  WHERE LOWER(TRIM(p.drug)) LIKE '%furosemide%' 
     OR LOWER(TRIM(p.drug)) LIKE '%lasix%' 
     OR LOWER(TRIM(p.drug)) LIKE '%bumetanide%' 
     OR LOWER(TRIM(p.drug)) LIKE '%torsemide%'

  UNION ALL

  -- ICU inputs: Loop Diuretic
  SELECT 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime,
    i.starttime, i.endtime AS stoptime,
    'Loop Diuretic' AS drug_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` i
    ON c.subject_id = i.subject_id AND CAST(c.hadm_id AS STRING) = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON i.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%furosemide%' 
     OR LOWER(di.label) LIKE '%lasix%' 
     OR i.itemid IN (225668, 225769)  -- Furosemide IV
),

window_flags AS (
  SELECT 
    m.hadm_id, m.drug_class,
    MAX(CASE WHEN m.starttime <= c.admittime + INTERVAL 1 DAY 
             AND (m.stoptime IS NULL OR m.stoptime > c.admittime) 
             THEN 1 ELSE 0 END) AS on_first24,
    MAX(CASE WHEN m.starttime <= c.dischtime 
             AND (m.stoptime IS NULL OR m.stoptime >= c.dischtime - INTERVAL 2 DAY) 
             THEN 1 ELSE 0 END) AS on_final48
  FROM med_events m
  INNER JOIN cohort c ON m.hadm_id = c.hadm_id
  GROUP BY m.hadm_id, m.drug_class
),

total_cohort AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_admissions FROM cohort
),

percents AS (
  SELECT 
    drug_class,
    ROUND(AVG(on_first24) * 100, 2) AS pct_first24,
    ROUND(AVG(on_final48) * 100, 2) AS pct_final48
  FROM window_flags
  GROUP BY drug_class
),

counts AS (
  SELECT 
    drug_class,
    SUM(CASE WHEN on_final48 = 1 AND on_first24 = 0 THEN 1 ELSE 0 END) AS initiated,
    SUM(CASE WHEN on_final48 = 1 AND on_first24 = 1 THEN 1 ELSE 0 END) AS continued,
    SUM(CASE WHEN on_final48 = 0 AND on_first24 = 1 THEN 1 ELSE 0 END) AS discontinued
  FROM window_flags
  GROUP BY drug_class
)

SELECT 
  p.drug_class,
  p.pct_first24,
  p.pct_final48,
  COALESCE(c.initiated, 0) AS initiated_count,
  COALESCE(c.continued, 0) AS continued_count,
  COALESCE(c.discontinued, 0) AS discontinued_count,
  t.total_admissions
FROM percents p
LEFT JOIN counts c ON p.drug_class = c.drug_class
CROSS JOIN total_cohort t
ORDER BY p.drug_class;