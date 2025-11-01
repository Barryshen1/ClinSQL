WITH eligible_hosp AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%') OR
          (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%') OR
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
-- Hosp: first 48h insulin signals
HospFirstWindow AS (
  SELECT e.hadm_id,
         MAX(CASE WHEN LOWER(p.drug) LIKE '%glargine%' OR LOWER(p.drug) LIKE '%detemir%' OR LOWER(p.drug) LIKE '%degludec%' THEN 1 ELSE 0 END) AS basal_first_hosp,
         MAX(CASE WHEN LOWER(p.drug) LIKE '%lispro%' OR LOWER(p.drug) LIKE '%aspart%' OR LOWER(p.drug) LIKE '%glulisine%' OR LOWER(p.drug) LIKE '%regular%' THEN 1 ELSE 0 END) AS bolus_first_hosp,
         MAX(CASE WHEN LOWER(p.drug) LIKE '%sliding scale%' OR LOWER(p.drug) LIKE '%sliding-scale%' THEN 1 ELSE 0 END) AS sliding_first_hosp
  FROM eligible_hosp e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.hadm_id = e.hadm_id
  WHERE p.starttime >= e.admittime
    AND p.starttime < TIMESTAMP_ADD(e.admittime, INTERVAL 48 HOUR)
  GROUP BY e.hadm_id
),
HospFinalWindow AS (
  SELECT e.hadm_id,
         MAX(CASE WHEN LOWER(p.drug) LIKE '%glargine%' OR LOWER(p.drug) LIKE '%detemir%' OR LOWER(p.drug) LIKE '%degludec%' THEN 1 ELSE 0 END) AS basal_final_hosp,
         MAX(CASE WHEN LOWER(p.drug) LIKE '%lispro%' OR LOWER(p.drug) LIKE '%aspart%' OR LOWER(p.drug) LIKE '%glulisine%' OR LOWER(p.drug) LIKE '%regular%' THEN 1 ELSE 0 END) AS bolus_final_hosp,
         MAX(CASE WHEN LOWER(p.drug) LIKE '%sliding scale%' OR LOWER(p.drug) LIKE '%sliding-scale%' THEN 1 ELSE 0 END) AS sliding_final_hosp
  FROM eligible_hosp e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.hadm_id = e.hadm_id
  WHERE p.starttime >= TIMESTAMP_SUB(e.dischtime, INTERVAL 12 HOUR)
    AND p.starttime < e.dischtime
  GROUP BY e.hadm_id
),
ICUFirstWindow AS (
  SELECT i.hadm_id,
         MAX(CASE WHEN LOWER(di.label) LIKE '%glargine%' OR LOWER(di.label) LIKE '%detemir%' OR LOWER(di.label) LIKE '%degludec%' THEN 1 ELSE 0 END) AS basal_first_icu,
         MAX(CASE WHEN LOWER(di.label) LIKE '%lispro%' OR LOWER(di.label) LIKE '%aspart%' OR LOWER(di.label) LIKE '%glulisine%' OR LOWER(di.label) LIKE '%regular%' THEN 1 ELSE 0 END) AS bolus_first_icu,
         MAX(CASE WHEN LOWER(di.label) LIKE '%sliding scale%' OR LOWER(di.label) LIKE '%sliding-scale%' THEN 1 ELSE 0 END) AS sliding_first_icu
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = i.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON a.hadm_id = i.hadm_id
  WHERE i.starttime >= a.admittime
    AND i.starttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY i.hadm_id
),
ICUFinalWindow_correct AS (
  SELECT i.hadm_id,
         MAX(CASE WHEN LOWER(di.label) LIKE '%glargine%' OR LOWER(di.label) LIKE '%detemir%' OR LOWER(di.label) LIKE '%degludec%' THEN 1 ELSE 0 END) AS basal_final_icu,
         MAX(CASE WHEN LOWER(di.label) LIKE '%lispro%' OR LOWER(di.label) LIKE '%aspart%' OR LOWER(di.label) LIKE '%glulisine%' OR LOWER(di.label) LIKE '%regular%' THEN 1 ELSE 0 END) AS bolus_final_icu,
         MAX(CASE WHEN LOWER(di.label) LIKE '%sliding scale%' OR LOWER(di.label) LIKE '%sliding-scale%' THEN 1 ELSE 0 END) AS sliding_final_icu
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = i.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON a.hadm_id = i.hadm_id
  WHERE i.starttime >= a.admittime
    AND i.starttime >= TIMESTAMP_SUB(a.dischtime, INTERVAL 12 HOUR)
    AND i.starttime < a.dischtime
  GROUP BY i.hadm_id
),
FirstBooleans AS (
  SELECT COALESCE(h.hadm_id, i.hadm_id) AS hadm_id,
         IF(COALESCE(h.basal_first_hosp, 0) + COALESCE(i.basal_first_icu, 0) > 0, 1, 0) AS basal_first,
         IF(COALESCE(h.bolus_first_hosp, 0) + COALESCE(i.bolus_first_icu, 0) > 0, 1, 0) AS bolus_first,
         IF(COALESCE(h.sliding_first_hosp, 0) + COALESCE(i.sliding_first_icu, 0) > 0, 1, 0) AS sliding_first
  FROM HospFirstWindow h
  FULL OUTER JOIN ICUFirstWindow i
    ON h.hadm_id = i.hadm_id
),
FinalBooleans AS (
  SELECT COALESCE(h.hadm_id, i.hadm_id) AS hadm_id,
         IF(COALESCE(h.basal_final_hosp, 0) + COALESCE(i.basal_final_icu, 0) > 0, 1, 0) AS basal_final,
         IF(COALESCE(h.bolus_final_hosp, 0) + COALESCE(i.bolus_final_icu, 0) > 0, 1, 0) AS bolus_final,
         IF(COALESCE(h.sliding_final_hosp, 0) + COALESCE(i.sliding_final_icu, 0) > 0, 1, 0) AS sliding_final
  FROM HospFinalWindow h
  FULL OUTER JOIN ICUFinalWindow_correct i
    ON h.hadm_id = i.hadm_id
),
FirstCategories AS (
  SELECT hadm_id,
         CASE
           WHEN sliding_first = 1 THEN 'sliding_scale'
           WHEN basal_first = 1 AND bolus_first = 1 THEN 'basal_bolus'
           WHEN basal_first = 1 THEN 'basal'
           WHEN bolus_first = 1 THEN 'bolus'
           ELSE NULL
         END AS category_first
  FROM FirstBooleans
),
FinalCategories AS (
  SELECT hadm_id,
         CASE
           WHEN sliding_final = 1 THEN 'sliding_scale'
           WHEN basal_final = 1 AND bolus_final = 1 THEN 'basal_bolus'
           WHEN basal_final = 1 THEN 'basal'
           WHEN bolus_final = 1 THEN 'bolus'
           ELSE NULL
         END AS category_final
  FROM FinalBooleans
),
FirstCounts AS (
  SELECT category_first AS category, COUNT(*) AS cnt
  FROM FirstCategories
  WHERE category_first IS NOT NULL
  GROUP BY category_first
),
FirstTotal AS (
  SELECT COUNT(*) AS total
  FROM FirstCategories
  WHERE category_first IS NOT NULL
),
FirstPct AS (
  SELECT fc.category,
         (fc.cnt / ft.total) * 100 AS percent_first48
  FROM FirstCounts fc
  CROSS JOIN FirstTotal ft
),
FinalCounts AS (
  SELECT category_final AS category, COUNT(*) AS cnt
  FROM FinalCategories
  WHERE category_final IS NOT NULL
  GROUP BY category_final
),
FinalTotal AS (
  SELECT COUNT(*) AS total
  FROM FinalCategories
  WHERE category_final IS NOT NULL
),
FinalPct AS (
  SELECT fc.category,
         (fc.cnt / ft.total) * 100 AS percent_final12
  FROM FinalCounts fc
  CROSS JOIN FinalTotal ft
)
SELECT
  f.category AS category,
  CAST(ROUND(p.percent_first48, 2) AS NUMERIC) AS percent_first48,
  CAST(ROUND(F.percent_final12, 2) AS NUMERIC) AS percent_final12,
  CAST(ROUND((F.percent_final12 - p.percent_first48), 2) AS NUMERIC) AS net_change
FROM FirstPct p
LEFT JOIN FinalPct F
  ON F.category = p.category
ORDER BY category;