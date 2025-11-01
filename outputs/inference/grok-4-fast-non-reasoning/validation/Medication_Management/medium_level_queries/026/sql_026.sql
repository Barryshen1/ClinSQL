WITH cohort_patients AS (
  -- Select female patients aged 38-48 (approx current age)
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age + 15 BETWEEN 38 AND 48  -- Approx age in 2023
    AND p.anchor_age > 18
    AND p.dod IS NULL
),

index_admissions AS (
  -- First admission per patient
  SELECT subject_id, hadm_id, admittime, dischtime,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN cohort_patients cp ON a.subject_id = cp.subject_id
  WHERE a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
  QUALIFY rn = 1
),

t2d_admissions AS (
  -- Admissions with T2D (E11.*)
  SELECT DISTINCT ia.subject_id, ia.hadm_id
  FROM index_admissions ia
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON ia.subject_id = di.subject_id AND ia.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON di.icd_code = icd.icd_code AND di.icd_version = icd.icd_version
  WHERE icd.icd_code LIKE 'E11%'
),

hf_admissions AS (
  -- Admissions with heart failure (I50.*, I11.0, I13.0, I13.2)
  SELECT DISTINCT ia.subject_id, ia.hadm_id
  FROM index_admissions ia
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON ia.subject_id = di.subject_id AND ia.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON di.icd_code = icd.icd_code AND di.icd_version = icd.icd_version
  WHERE icd.icd_code LIKE 'I50%' OR icd.icd_code IN ('I11.0', 'I13.0', 'I13.2')
),

eligible_admissions AS (
  -- Admissions with both T2D and HF
  SELECT ta.subject_id, ta.hadm_id, ia.admittime, ia.dischtime
  FROM t2d_admissions ta
  INNER JOIN hf_admissions ha ON ta.subject_id = ha.subject_id AND ta.hadm_id = ha.hadm_id
  INNER JOIN index_admissions ia ON ta.hadm_id = ia.hadm_id
),

prior_meds AS (
  -- Flag prior antidiabetic use (7 days before admission)
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    CASE 
      WHEN ie.itemid IN (30009, 30047, 30044) THEN 'insulin'
      WHEN ie.itemid BETWEEN 225907 AND 225915 THEN 'oral'  -- Common orals: metformin, etc.
      ELSE NULL 
    END AS med_type
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  INNER JOIN eligible_admissions ea ON ie.subject_id = ea.subject_id AND ie.hadm_id = ea.hadm_id
  WHERE ie.itemid IN (30009, 30047, 30044, 225907, 225908, 225910, 225911, 225912, 225914, 225915)  -- Insulin + key orals
    AND ie.amount > 0
    AND ie.starttime < ea.admittime
    AND ie.starttime >= TIMESTAMP_SUB(ea.admittime, INTERVAL 7 DAY)

  UNION ALL

  SELECT 
    p.subject_id,
    p.hadm_id,
    CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(p.drug) IN ('metformin', 'glipizide', 'glyburide', 'glimepiride', 'sitagliptin', 'linagliptin') THEN 'oral'  -- Key orals
      ELSE NULL 
    END AS med_type
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN eligible_admissions ea ON p.subject_id = ea.subject_id AND p.hadm_id = ea.hadm_id
  WHERE (LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) IN ('metformin', 'glipizide', 'glyburide', 'glimepiride', 'sitagliptin', 'linagliptin'))
    AND p.starttime < ea.admittime
    AND p.starttime >= TIMESTAMP_SUB(ea.admittime, INTERVAL 7 DAY)
),

med_events AS (
  -- All med events during admission (ICU + HOSP)
  SELECT 
    subject_id,
    hadm_id,
    starttime,
    itemid,
    drug,
    amount
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  INNER JOIN eligible_admissions ea ON ie.subject_id = ea.subject_id AND ie.hadm_id = ie.hadm_id
  WHERE ie.starttime >= ea.admittime 
    AND ie.starttime <= ea.dischtime
    AND ie.amount > 0
    AND ie.itemid IN (30009, 30047, 30044, 225907, 225908, 225910, 225911, 225912, 225914, 225915)

  UNION ALL

  SELECT 
    subject_id,
    hadm_id,
    starttime,
    NULL AS itemid,
    drug,
    NULL AS amount
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN eligible_admissions ea ON p.subject_id = ea.subject_id AND p.hadm_id = p.hadm_id
  WHERE p.starttime >= ea.admittime 
    AND p.starttime <= ea.dischtime
    AND (LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) IN ('metformin', 'glipizide', 'glyburide', 'glimepiride', 'sitagliptin', 'linagliptin'))
),

classified_initiations AS (
  -- Classify events into windows and med_types, exclude priors
  SELECT DISTINCT
    ea.subject_id,
    ea.hadm_id,
    ea.admittime,
    ea.dischtime,
    CASE 
      WHEN me.starttime >= ea.admittime AND me.starttime < TIMESTAMP_ADD(ea.admittime, INTERVAL 72 HOUR) THEN 'first_72h'
      WHEN me.starttime >= TIMESTAMP_SUB(ea.dischtime, INTERVAL 72 HOUR) AND me.starttime <= ea.dischtime THEN 'final_72h'
      ELSE NULL 
    END AS window,
    CASE 
      WHEN me.itemid IN (30009, 30047, 30044) OR LOWER(me.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN me.itemid BETWEEN 225907 AND 225915 OR LOWER(me.drug) IN ('metformin', 'glipizide', 'glyburide', 'glimepiride', 'sitagliptin', 'linagliptin') THEN 'oral'
      ELSE NULL 
    END AS med_type
  FROM med_events me
  INNER JOIN eligible_admissions ea ON me.subject_id = ea.subject_id AND me.hadm_id = ea.hadm_id
  WHERE med_type IS NOT NULL  -- Valid med_type
    AND window IS NOT NULL  -- In target windows
    AND NOT EXISTS (
      SELECT 1 
      FROM prior_meds pm 
      WHERE pm.subject_id = ea.subject_id 
        AND pm.hadm_id = ea.hadm_id 
        AND pm.med_type = classified_initiations.med_type
    )
),

initiated_patients AS (
  SELECT 
    window,
    med_type,
    COUNT(DISTINCT subject_id) AS num_patients
  FROM classified_initiations
  GROUP BY window, med_type
),

total_initiated AS (
  SELECT window, SUM(num_patients) AS total
  FROM initiated_patients
  GROUP BY window
)

-- Final percentages
SELECT 
  ip.window,
  ROUND(SUM(CASE WHEN ip.med_type = 'insulin' THEN ip.num_patients ELSE 0 END) * 100.0 / ti.total, 2) AS insulin_pct,
  ROUND(SUM(CASE WHEN ip.med_type = 'oral' THEN ip.num_patients ELSE 0 END) * 100.0 / ti.total, 2) AS oral_pct
FROM initiated_patients ip
INNER JOIN total_initiated ti ON ip.window = ti.window
GROUP BY ip.window, ti.total
ORDER BY CASE WHEN window = 'first_72h' THEN 1 ELSE 2 END;