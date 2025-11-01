WITH cohort AS (
  -- Base cohort: females 54-64 with diabetes and heart failure
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = CAST(i.hadm_id AS INT64)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 54 AND 64
    AND EXTRACT(YEAR FROM a.admittime) >= p.anchor_year
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND d.icd_version = '10'
    AND (
      -- Diabetes (E10-E13)
      d.icd_code LIKE 'E1[0-3]%'
      OR d.icd_code IN ('E10', 'E11', 'E12', 'E13')
    )
    AND (
      -- Heart failure (I50.* or combinations)
      d.icd_code LIKE 'I50.%'
      OR (d.icd_code IN ('I09.81', 'I11.0', 'I13.0', 'I13.2') AND EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
        WHERE d2.subject_id = d.subject_id 
          AND d2.hadm_id = d.hadm_id
          AND d2.icd_version = '10'
          AND d2.icd_code LIKE 'I50.%'
      ))
    )
    AND i.los > 0  -- Valid ICU stay
),

first_12h_insulin AS (
  -- Insulin in first 12h
  SELECT c.hadm_id,
    CASE WHEN COUNT(DISTINCT ie.itemid) > 0 THEN 1 ELSE 0 END AS has_insulin_first
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.subject_id = i.subject_id AND c.hadm_id = CAST(i.hadm_id AS INT64)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON i.stay_id = ie.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE i.los >= 0.5  -- At least 12h stay
    AND ie.starttime >= i.intime
    AND ie.starttime <= DATETIME_ADD(i.intime, INTERVAL 12 HOUR)
    AND ie.amount > 0
    AND ie.statusdescription != 'Rewritten'
    AND (LOWER(di.label) LIKE '%insulin%' OR ie.itemid IN (225798, 225829, 225831, 225802, 225803))
  GROUP BY c.hadm_id
),

final_48h_insulin AS (
  -- Insulin in final 48h (only if stay >=48h)
  SELECT c.hadm_id,
    CASE WHEN COUNT(DISTINCT ie.itemid) > 0 THEN 1 ELSE 0 END AS has_insulin_final
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.subject_id = i.subject_id AND c.hadm_id = CAST(i.hadm_id AS INT64)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON i.stay_id = ie.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE i.los >= 2  -- At least 48h stay
    AND ie.starttime >= DATETIME_SUB(i.outtime, INTERVAL 48 HOUR)
    AND ie.starttime <= i.outtime
    AND ie.amount > 0
    AND ie.statusdescription != 'Rewritten'
    AND (LOWER(di.label) LIKE '%insulin%' OR ie.itemid IN (225798, 225829, 225831, 225802, 225803))
  GROUP BY c.hadm_id
),

first_12h_oral AS (
  -- Oral agents in first 12h (prescription overlap)
  SELECT c.hadm_id,
    CASE WHEN COUNT(DISTINCT pr.pharmacy_id) > 0 THEN 1 ELSE 0 END AS has_oral_first
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.subject_id = i.subject_id AND c.hadm_id = CAST(i.hadm_id AS INT64)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  WHERE i.los >= 0.5  -- At least 12h stay
    AND pr.starttime <= DATETIME_ADD(i.intime, INTERVAL 12 HOUR)
    AND (pr.stoptime IS NULL OR pr.stoptime > i.intime)
    AND pr.dose_val_rx > 0
    AND (LOWER(pr.drug) LIKE '%metformin%' 
         OR LOWER(pr.drug) LIKE '%glipizide%' 
         OR LOWER(pr.drug) LIKE '%glyburide%' 
         OR LOWER(pr.drug) LIKE '%pioglitazone%' 
         OR LOWER(pr.drug) LIKE '%sitagliptin%'
         OR LOWER(pr.drug) LIKE '%sulfonylurea%'
         OR LOWER(pr.drug) LIKE '%empagliflozin%')
  GROUP BY c.hadm_id
),

final_48h_oral AS (
  -- Oral agents in final 48h
  SELECT c.hadm_id,
    CASE WHEN COUNT(DISTINCT pr.pharmacy_id) > 0 THEN 1 ELSE 0 END AS has_oral_final
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.subject_id = i.subject_id AND c.hadm_id = CAST(i.hadm_id AS INT64)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  WHERE i.los >= 2  -- At least 48h stay
    AND pr.starttime <= i.outtime
    AND (pr.stoptime IS NULL OR pr.stoptime > DATETIME_SUB(i.outtime, INTERVAL 48 HOUR))
    AND pr.dose_val_rx > 0
    AND (LOWER(pr.drug) LIKE '%metformin%' 
         OR LOWER(pr.drug) LIKE '%glipizide%' 
         OR LOWER(pr.drug) LIKE '%glyburide%' 
         OR LOWER(pr.drug) LIKE '%pioglitazone%' 
         OR LOWER(pr.drug) LIKE '%sitagliptin%'
         OR LOWER(pr.drug) LIKE '%sulfonylurea%'
         OR LOWER(pr.drug) LIKE '%empagliflozin%')
  GROUP BY c.hadm_id
)

-- Aggregate prevalences and net change
SELECT 
  COUNT(DISTINCT c.hadm_id) AS cohort_size,
  ROUND(AVG(COALESCE(f12i.has_insulin_first, 0)) * 100, 2) AS insulin_first_12h_pct,
  ROUND(AVG(COALESCE(f48i.has_insulin_final, 0)) * 100, 2) AS insulin_final_48h_pct,
  ROUND((AVG(COALESCE(f48i.has_insulin_final, 0)) - AVG(COALESCE(f12i.has_insulin_first, 0))) * 100, 2) AS insulin_net_change_pp,
  ROUND(AVG(COALESCE(f12o.has_oral_first, 0)) * 100, 2) AS oral_first_12h_pct,
  ROUND(AVG(COALESCE(f48o.has_oral_final, 0)) * 100, 2) AS oral_final_48h_pct,
  ROUND((AVG(COALESCE(f48o.has_oral_final, 0)) - AVG(COALESCE(f12o.has_oral_first, 0))) * 100, 2) AS oral_net_change_pp
FROM cohort c
LEFT JOIN first_12h_insulin f12i ON c.hadm_id = f12i.hadm_id
LEFT JOIN final_48h_insulin f48i ON c.hadm_id = f48i.hadm_id
LEFT JOIN first_12h_oral f12o ON c.hadm_id = f12o.hadm_id
LEFT JOIN final_48h_oral f48o ON c.hadm_id = f48o.hadm_id;