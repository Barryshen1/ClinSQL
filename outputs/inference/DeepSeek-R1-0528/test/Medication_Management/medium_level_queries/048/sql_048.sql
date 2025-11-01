WITH cohort AS (
  SELECT 
      adm.subject_id, 
      adm.hadm_id, 
      adm.admittime, 
      adm.dischtime,
      p.anchor_age,
      p.anchor_year,
      p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON adm.subject_id = p.subject_id
  WHERE 
      p.gender = 'F'
      AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 65 AND 75
      AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 96
      -- Diabetes diagnosis (fixed parentheses)
      AND EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
          WHERE 
              ( (di.icd_code LIKE '250%' AND di.icd_version = 9) 
                OR 
                (di.icd_code LIKE 'E1%' AND di.icd_version = 10) 
              )
              AND di.subject_id = adm.subject_id 
              AND di.hadm_id = adm.hadm_id
      )
      -- Heart failure diagnosis (fixed parentheses)
      AND EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
          WHERE 
              ( (di.icd_code LIKE '428%' AND di.icd_version = 9) 
                OR 
                (di.icd_code LIKE 'I50%' AND di.icd_version = 10) 
              )
              AND di.subject_id = adm.subject_id 
              AND di.hadm_id = adm.hadm_id
      )
),

insulin_events AS (
  -- EMAR (non-ICU administrations)
  SELECT 
      em.subject_id,
      em.hadm_id,
      em.charttime,
      em.medication,
      em.event_txt,
      CASE 
          WHEN LOWER(em.medication) LIKE '%glargine%' OR 
               LOWER(em.medication) LIKE '%detemir%' OR 
               LOWER(em.medication) LIKE '%degludec%' OR 
               LOWER(em.medication) LIKE '%NPH%' OR 
               LOWER(em.medication) LIKE '%isophane%' THEN 1
          ELSE 0 
      END AS is_basal,
      CASE 
          WHEN LOWER(em.medication) LIKE '%aspart%' OR 
               LOWER(em.medication) LIKE '%lispro%' OR 
               LOWER(em.medication) LIKE '%regular%' OR 
               LOWER(em.medication) LIKE '%humalog%' OR 
               LOWER(em.medication) LIKE '%novolog%' OR 
               LOWER(em.medication) LIKE '%apidra%' THEN 1
          ELSE 0 
      END AS is_bolus,
      CASE 
          WHEN LOWER(em.event_txt) LIKE '%sliding%' OR 
               LOWER(em.medication) LIKE '%sliding%' OR 
               LOWER(em.event_txt) LIKE '%ssi%' OR 
               LOWER(em.medication) LIKE '%ssi%' OR 
               LOWER(em.event_txt) LIKE '%ssri%' OR 
               LOWER(em.medication) LIKE '%ssri%' THEN 1
          ELSE 0 
      END AS is_sliding
  FROM `physionet-data.mimiciv_3_1_hosp.emar` em
  WHERE LOWER(em.medication) LIKE '%insulin%'

  UNION ALL

  -- Inputevents (ICU administrations)
  SELECT 
      i.subject_id,
      ie.hadm_id,
      i.starttime AS charttime,
      d.label AS medication,
      NULL AS event_txt,
      CASE 
          WHEN LOWER(d.label) LIKE '%glargine%' OR 
               LOWER(d.label) LIKE '%detemir%' OR 
               LOWER(d.label) LIKE '%degludec%' OR 
               LOWER(d.label) LIKE '%NPH%' OR 
               LOWER(d.label) LIKE '%isophane%' THEN 1
          ELSE 0 
      END AS is_basal,
      CASE 
          WHEN LOWER(d.label) LIKE '%aspart%' OR 
               LOWER(d.label) LIKE '%lispro%' OR 
               LOWER(d.label) LIKE '%regular%' OR 
               LOWER(d.label) LIKE '%humalog%' OR 
               LOWER(d.label) LIKE '%novolog%' OR 
               LOWER(d.label) LIKE '%apidra%' THEN 1
          ELSE 0 
      END AS is_bolus,
      CASE 
          WHEN LOWER(d.label) LIKE '%sliding%' OR 
               LOWER(d.label) LIKE '%ssi%' OR 
               LOWER(d.label) LIKE '%ssri%' THEN 1
          ELSE 0 
      END AS is_sliding
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
      ON i.itemid = d.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
      ON i.stay_id = ie.stay_id
  WHERE LOWER(d.label) LIKE '%insulin%'
),

insulin_with_cohort AS (
  SELECT 
      c.subject_id,
      c.hadm_id,
      c.admittime,
      c.dischtime,
      ie.charttime,
      ie.is_basal,
      ie.is_bolus,
      ie.is_sliding,
      -- First 48h flag
      CASE WHEN ie.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END AS in_first_48h,
      -- Final 48h flag
      CASE WHEN ie.charttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1 ELSE 0 END AS in_final_48h
  FROM cohort c
  INNER JOIN insulin_events ie
      ON c.subject_id = ie.subject_id AND c.hadm_id = ie.hadm_id
),

regimen_flags AS (
  SELECT 
      subject_id,
      hadm_id,
      -- First 48h regimens
      MAX(CASE WHEN in_first_48h = 1 AND is_basal = 1 THEN 1 ELSE 0 END) AS basal_first,
      MAX(CASE WHEN in_first_48h = 1 AND is_bolus = 1 THEN 1 ELSE 0 END) AS bolus_first,
      MAX(CASE WHEN in_first_48h = 1 AND is_basal = 1 AND is_bolus = 1 THEN 1 ELSE 0 END) AS basal_bolus_first,
      MAX(CASE WHEN in_first_48h = 1 AND is_sliding = 1 THEN 1 ELSE 0 END) AS sliding_first,
      -- Final 48h regimens
      MAX(CASE WHEN in_final_48h = 1 AND is_basal = 1 THEN 1 ELSE 0 END) AS basal_final,
      MAX(CASE WHEN in_final_48h = 1 AND is_bolus = 1 THEN 1 ELSE 0 END) AS bolus_final,
      MAX(CASE WHEN in_final_48h = 1 AND is_basal = 1 AND is_bolus = 1 THEN 1 ELSE 0 END) AS basal_bolus_final,
      MAX(CASE WHEN in_final_48h = 1 AND is_sliding = 1 THEN 1 ELSE 0 END) AS sliding_final
  FROM insulin_with_cohort
  GROUP BY subject_id, hadm_id
)

SELECT 
    COUNT(*) AS total_patients,
    -- First 48h percentages
    ROUND(100.0 * SUM(basal_first) / COUNT(*), 1) AS pct_basal_first,
    ROUND(100.0 * SUM(bolus_first) / COUNT(*), 1) AS pct_bolus_first,
    ROUND(100.0 * SUM(basal_bolus_first) / COUNT(*), 1) AS pct_basal_bolus_first,
    ROUND(100.0 * SUM(sliding_first) / COUNT(*), 1) AS pct_sliding_first,
    -- Final 48h percentages
    ROUND(100.0 * SUM(basal_final) / COUNT(*), 1) AS pct_basal_final,
    ROUND(100.0 * SUM(bolus_final) / COUNT(*), 1) AS pct_bolus_final,
    ROUND(100.0 * SUM(basal_bolus_final) / COUNT(*), 1) AS pct_basal_bolus_final,
    ROUND(100.0 * SUM(sliding_final) / COUNT(*), 1) AS pct_sliding_final
FROM regimen_flags;