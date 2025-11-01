WITH cohort AS (
  -- Base cohort: 60-70 yo females with T2DM + HF, first ICU stay
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    i.stay_id,
    i.hadm_id,
    i.intime,
    a.dischtime,
    i.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN (
    SELECT 
      subject_id,
      stay_id,
      hadm_id,
      intime,
      los,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i ON p.subject_id = i.subject_id AND i.rn = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70
    AND i.los >= 0  -- All stays
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.subject_id = p.subject_id 
        AND d.hadm_id = i.hadm_id
        AND (
          (d.icd_version = '10' AND d.icd_code LIKE 'E11.%') OR 
          (d.icd_version = '9' AND d.icd_code LIKE '250.4%')  -- T2DM for ICD-9
        )
    )
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.subject_id = p.subject_id 
        AND d.hadm_id = i.hadm_id
        AND (
          (d.icd_version = '10' AND d.icd_code LIKE 'I50.%') OR
          (d.icd_version = '9' AND d.icd_code LIKE '428%')
        )
    )
),
early_meds AS (
  -- Initiation in first 48h (ICU inputs/ingredients)
  SELECT 
    c.subject_id,
    CASE 
      WHEN ie.itemid IN (225798, 225799, 225828, 225831, 225798, 220939, 221748) THEN 'antidiabetics'  -- Insulin variants
      WHEN ie.itemid IN (222469, 222970, 223758, 228351) THEN 'beta_blockers'  -- Metoprolol, etc.
      WHEN ie.itemid IN (225773, 225775, 225776) THEN 'acei_arb_arni'  -- Lisinopril, etc. (extend with ARBs if needed)
      WHEN ie.itemid IN (225807, 225828, 221203) THEN 'loop_diuretics'  -- Furosemide, etc.
    END AS med_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie ON c.subject_id = ie.subject_id AND c.stay_id = ie.stay_id
  WHERE ie.starttime >= c.intime 
    AND (ie.endtime <= c.intime + INTERVAL 48 HOUR OR ie.endtime IS NULL)
    AND ie.amount > 0
  UNION ALL
  SELECT 
    c.subject_id,
    CASE 
      WHEN ing.itemid IN (50071, 50072, 50073) THEN 'antidiabetics'  -- Insulin med IDs
      WHEN ing.itemid IN (50006, 50007) THEN 'beta_blockers'
      WHEN ing.itemid IN (50010, 50011) THEN 'acei_arb_arni'
      WHEN ing.itemid IN (50015) THEN 'loop_diuretics'
    END AS med_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.ingredientevents` ing ON c.subject_id = ing.subject_id AND c.stay_id = ing.stay_id
  WHERE ing.starttime >= c.intime 
    AND (ing.endtime <= c.intime + INTERVAL 48 HOUR OR ing.endtime IS NULL)
    AND ing.amount > 0
),
late_meds AS (
  -- Initiation in final 24h (prescriptions, hospital-wide)
  SELECT 
    c.subject_id,
    CASE 
      WHEN LOWER(pr.drug) LIKE '%insulin%' OR LOWER(pr.drug) LIKE '%metformin%' THEN 'antidiabetics'
      WHEN LOWER(pr.drug) LIKE '%metoprolol%' OR LOWER(pr.drug) LIKE '%beta blocker%' THEN 'beta_blockers'
      WHEN LOWER(pr.drug) LIKE '%lisinopril%' OR LOWER(pr.drug) LIKE '%losartan%' OR LOWER(pr.drug) LIKE '%sacubitril%' THEN 'acei_arb_arni'
      WHEN LOWER(pr.drug) LIKE '%furosemide%' OR LOWER(pr.drug) LIKE '%lasix%' OR LOWER(pr.drug) LIKE '%bumetanide%' THEN 'loop_diuretics'
    END AS med_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  WHERE pr.starttime <= c.dischtime 
    AND (pr.stoptime >= DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) OR pr.stoptime IS NULL)
    AND pr.dose_val_rx > 0
),
summary AS (
  SELECT 
    'antidiabetics' AS med_class,
    COUNT(DISTINCT em.subject_id) * 100.0 / COUNT(DISTINCT c.subject_id) AS early_pct,
    COUNT(DISTINCT lm.subject_id) * 100.0 / COUNT(DISTINCT c.subject_id) AS late_pct
  FROM cohort c
  LEFT JOIN early_meds em ON c.subject_id = em.subject_id AND em.med_class = 'antidiabetics'
  LEFT JOIN late_meds lm ON c.subject_id = lm.subject_id AND lm.med_class = 'antidiabetics'
  UNION ALL
  SELECT 
    'beta_blockers' AS med_class,
    COUNT(DISTINCT em.subject_id) * 100.0 / COUNT(DISTINCT c.subject_id) AS early_pct,
    COUNT(DISTINCT lm.subject_id) * 100.0 / COUNT(DISTINCT c.subject_id) AS late_pct
  FROM cohort c
  LEFT JOIN early_meds em ON c.subject_id = em.subject_id AND em.med_class = 'beta_blockers'
  LEFT JOIN late_meds lm ON c.subject_id = lm.subject_id AND lm.med_class = 'beta_blockers'
  UNION ALL
  SELECT 
    'acei_arb_arni' AS med_class,
    COUNT(DISTINCT em.subject_id) * 100.0 / COUNT(DISTINCT c.subject_id) AS early_pct,
    COUNT(DISTINCT lm.subject_id) * 100.0 / COUNT(DISTINCT c.subject_id) AS late_pct
  FROM cohort c
  LEFT JOIN early_meds em ON c.subject_id = em.subject_id AND em.med_class = 'acei_arb_arni'
  LEFT JOIN late_meds lm ON c.subject_id = lm.subject_id AND lm.med_class = 'acei_arb_arni'
  UNION ALL
  SELECT 
    'loop_diuretics' AS med_class,
    COUNT(DISTINCT em.subject_id) * 100.0 / COUNT(DISTINCT c.subject_id) AS early_pct,
    COUNT(DISTINCT lm.subject_id) * 100.0 / COUNT(DISTINCT c.subject_id) AS late_pct
  FROM cohort c
  LEFT JOIN early_meds em ON c.subject_id = em.subject_id AND em.med_class = 'loop_diuretics'
  LEFT JOIN late_meds lm ON c.subject_id = lm.subject_id AND lm.med_class = 'loop_diuretics'
)
SELECT 
  med_class,
  ROUND(early_pct, 2) AS initiation_first_48h_pct,
  ROUND(late_pct, 2) AS initiation_final_24h_pct,
  ROUND(late_pct - early_pct, 2) AS absolute_difference_pp
FROM summary
ORDER BY med_class;